package com.ssafy.b209.analysis.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.repository.AnalysisResultJdbcRepository;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class DrawingAnalysisPersistenceServiceTest {

  private static final long SESSION_ID = 10L;
  private static final long ASSET_ID = 20L;
  private static final long ANALYSIS_ID = 30L;
  private static final LocalDateTime REQUESTED_AT = LocalDateTime.parse("2026-07-22T05:00:00");
  private static final LocalDateTime PROCESSED_AT = LocalDateTime.parse("2026-07-22T05:00:01");

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private DrawingAnalysisRepository drawingAnalysisRepository;
  @Mock private AnalysisResultJdbcRepository analysisResultJdbcRepository;
  @Mock private DrawingSession session;
  @Mock private DrawingAsset asset;

  private DrawingAnalysisPersistenceService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingAnalysisPersistenceService(
            drawingSessionRepository,
            drawingAssetRepository,
            drawingAnalysisRepository,
            analysisResultJdbcRepository);
  }

  @Test
  void startsProcessingAnalysisForFinalAssetInSameSession() {
    givenValidTarget();
    given(asset.getStorageKey()).willReturn("drawing/final.png");
    given(asset.getMimeType()).willReturn("image/png");
    given(drawingAnalysisRepository.saveAndFlush(any(DrawingAnalysis.class)))
        .willAnswer(
            invocation -> {
              DrawingAnalysis analysis = invocation.getArgument(0);
              ReflectionTestUtils.setField(analysis, "id", ANALYSIS_ID);
              return analysis;
            });

    StartedDrawingAnalysis started =
        service.start(
            SESSION_ID,
            ASSET_ID,
            DrawingAnalysisType.OBJECT_DETECTION,
            "550e8400-e29b-41d4-a716-446655440000",
            REQUESTED_AT);

    assertThat(started.analysisId()).isEqualTo(ANALYSIS_ID);
    assertThat(started.storageKey()).isEqualTo("drawing/final.png");
    assertThat(started.contentType()).isEqualTo("image/png");
    assertThat(started.requestedAt()).isEqualTo(REQUESTED_AT);
    ArgumentCaptor<DrawingAnalysis> captor = ArgumentCaptor.forClass(DrawingAnalysis.class);
    verify(drawingAnalysisRepository).saveAndFlush(captor.capture());
    assertThat(ReflectionTestUtils.getField(captor.getValue(), "scope"))
        .isEqualTo(DrawingAnalysisScope.FINAL);
    verify(session, never()).startDrawingAnalysis();
  }

  @Test
  void startsDrawingStageCompletionAndMovesTheSessionToAnalyzing() {
    givenValidTarget();
    given(asset.getStorageKey()).willReturn("drawing/final.png");
    given(asset.getMimeType()).willReturn("image/png");
    given(drawingAnalysisRepository.saveAndFlush(any(DrawingAnalysis.class)))
        .willAnswer(
            invocation -> {
              DrawingAnalysis analysis = invocation.getArgument(0);
              ReflectionTestUtils.setField(analysis, "id", ANALYSIS_ID);
              return analysis;
            });

    service.startForDrawingCompletion(
        SESSION_ID,
        ASSET_ID,
        DrawingAnalysisType.OBJECT_DETECTION,
        "drawing-complete-key",
        REQUESTED_AT);

    verify(session).startDrawingAnalysis();
  }

  @Test
  void savesCanonicalSupplementalResultsInTheCompletionTransaction() {
    DrawingAnalysis processing =
        DrawingAnalysis.processing(
            session,
            asset,
            DrawingAnalysisScope.FINAL,
            DrawingAnalysisType.OBJECT_DETECTION,
            "request-1",
            REQUESTED_AT);
    ReflectionTestUtils.setField(processing, "id", ANALYSIS_ID);
    given(drawingAnalysisRepository.findByIdForUpdate(ANALYSIS_ID))
        .willReturn(Optional.of(processing));
    given(session.getCurrentStage())
        .willReturn(com.ssafy.b209.drawing.domain.DrawingStage.ANALYZING);
    var model =
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.ModelRef(
            "yolo", "1.0");
    var response =
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse(
            ANALYSIS_ID,
            com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
                .AnalysisStatus.PARTIAL_SUCCESS,
            new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
                .ModelInfo(model, null, null, null),
            List.of(),
            Map.of("inkRatio", new BigDecimal("0.2")),
            Map.of("pressureAvailable", false),
            null,
            null,
            List.of(),
            List.of(
                new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
                    .UnusedInput("PRESSURE", "DEVICE_NOT_SUPPORTED", null, false)),
            List.of("PRESSURE_DATA_UNAVAILABLE"),
            10L);

    service.completeCanonical(ANALYSIS_ID, response, PROCESSED_AT);

    assertThat(processing.getState()).isEqualTo(DrawingAnalysisState.PARTIAL_SUCCESS);
    verify(analysisResultJdbcRepository).replace(ANALYSIS_ID, response, PROCESSED_AT);
    verify(session).finishDrawingAnalysis();
  }

  @Test
  void startsIntermediateObjectDetectionForDraftAsset() {
    givenValidTarget();
    given(asset.getAssetType()).willReturn(DrawingAssetType.DRAFT);
    given(asset.getStorageKey()).willReturn("drawing/draft.png");
    given(asset.getMimeType()).willReturn("image/png");
    given(drawingAnalysisRepository.saveAndFlush(any(DrawingAnalysis.class)))
        .willAnswer(invocation -> invocation.getArgument(0));

    StartedDrawingAnalysis started =
        service.start(
            SESSION_ID,
            ASSET_ID,
            DrawingAnalysisType.OBJECT_DETECTION,
            "550e8400-e29b-41d4-a716-446655440000",
            REQUESTED_AT);

    assertThat(started.storageKey()).isEqualTo("drawing/draft.png");
    ArgumentCaptor<DrawingAnalysis> captor = ArgumentCaptor.forClass(DrawingAnalysis.class);
    verify(drawingAnalysisRepository).saveAndFlush(captor.capture());
    assertThat(ReflectionTestUtils.getField(captor.getValue(), "scope"))
        .isEqualTo(DrawingAnalysisScope.INTERMEDIATE);
    verify(session, never()).startDrawingAnalysis();
  }

  @Test
  void rejectsMissingAndInvalidAnalysisTargets() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.empty());

    assertError(
        () ->
            service.start(
                SESSION_ID, ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION, "id", REQUESTED_AT),
        com.ssafy.b209.drawing.exception.DrawingErrorCode.DRAWING_SESSION_NOT_FOUND);

    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(session));
    given(session.isAnalysisRequestable()).willReturn(true);
    given(drawingAssetRepository.findById(ASSET_ID)).willReturn(Optional.empty());

    assertError(
        () ->
            service.start(
                SESSION_ID, ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION, "id", REQUESTED_AT),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_TARGET_NOT_FOUND);
    verify(drawingAnalysisRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsAssetFromAnotherSessionAndUnsupportedAssetType() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(session));
    given(session.isAnalysisRequestable()).willReturn(true);
    given(session.getId()).willReturn(SESSION_ID);
    given(drawingAssetRepository.findById(ASSET_ID)).willReturn(Optional.of(asset));
    DrawingSession otherSession = mock(DrawingSession.class);
    given(otherSession.getId()).willReturn(99L);
    given(asset.getDrawingSession()).willReturn(otherSession);

    assertError(
        () ->
            service.start(
                SESSION_ID, ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION, "id", REQUESTED_AT),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);

    given(asset.getDrawingSession()).willReturn(session);
    given(asset.getAssetType()).willReturn(DrawingAssetType.INTERMEDIATE);
    assertError(
        () ->
            service.start(
                SESSION_ID, ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION, "id", REQUESTED_AT),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
  }

  @Test
  void rejectsActivityReportFromPublicAnalysisRequest() {
    givenValidTarget();

    assertError(
        () ->
            service.start(
                SESSION_ID, ASSET_ID, DrawingAnalysisType.ACTIVITY_REPORT, "id", REQUESTED_AT),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);

    given(asset.getAssetType()).willReturn(DrawingAssetType.DRAFT);
    assertError(
        () ->
            service.start(
                SESSION_ID, ASSET_ID, DrawingAnalysisType.ACTIVITY_REPORT, "id", REQUESTED_AT),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
    verify(drawingAnalysisRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsProcessingOrSuccessfulDuplicateButAllowsFailedHistory() {
    givenValidTarget();
    given(
            drawingAnalysisRepository.existsActiveByAssetAndTaskType(
                ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION))
        .willReturn(true);

    assertError(
        () ->
            service.start(
                SESSION_ID, ASSET_ID, DrawingAnalysisType.OBJECT_DETECTION, "id", REQUESTED_AT),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_ALREADY_EXISTS);
    verify(drawingAnalysisRepository, never()).saveAndFlush(any());
  }

  @Test
  void preservesFailedAnalysisRow() {
    DrawingAnalysis analysis = processingAnalysis();
    given(drawingAnalysisRepository.findByIdForUpdate(ANALYSIS_ID))
        .willReturn(Optional.of(analysis));
    given(session.getCurrentStage())
        .willReturn(com.ssafy.b209.drawing.domain.DrawingStage.ANALYZING);

    service.fail(ANALYSIS_ID, "TIMEOUT", "그림 분석 요청을 완료하지 못했습니다.", PROCESSED_AT);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.FAILED);
    assertThat(analysis.getErrorCode()).isEqualTo("TIMEOUT");
    verify(drawingAnalysisRepository).flush();
    verify(session).finishDrawingAnalysis();
  }

  @Test
  void findsStoredAnalysisSummaryByRequestId() {
    DrawingAnalysis analysis = processingAnalysis();
    given(session.getId()).willReturn(SESSION_ID);
    given(asset.getId()).willReturn(ASSET_ID);
    given(session.getSessionStatus())
        .willReturn(com.ssafy.b209.drawing.domain.DrawingSessionStatus.IN_PROGRESS);
    given(session.getCurrentStage())
        .willReturn(com.ssafy.b209.drawing.domain.DrawingStage.ANALYZING);
    given(drawingAnalysisRepository.findByRequestId("drawing-complete-key"))
        .willReturn(Optional.of(analysis));

    DrawingAnalysisRequestSummary summary =
        service.findByRequestId("drawing-complete-key").orElseThrow();

    assertThat(summary.analysisId()).isEqualTo(ANALYSIS_ID);
    assertThat(summary.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(summary.drawingAssetId()).isEqualTo(ASSET_ID);
    assertThat(summary.taskType()).isEqualTo(DrawingAnalysisType.OBJECT_DETECTION);
    assertThat(summary.state()).isEqualTo(DrawingAnalysisState.PROCESSING);
    assertThat(summary.currentStage())
        .isEqualTo(com.ssafy.b209.drawing.domain.DrawingStage.ANALYZING);
  }

  @Test
  void rejectsRetryWhenTheSourceAnalysisHasNotFailed() {
    DrawingAnalysis source = processingAnalysis();
    given(drawingAnalysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(source));

    assertError(
        () ->
            service.startRetry(
                ANALYSIS_ID, false, "660e8400-e29b-41d4-a716-446655440000", PROCESSED_AT),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RETRY_NOT_ALLOWED);

    verify(drawingAnalysisRepository, never()).saveAndFlush(any());
  }

  private void givenValidTarget() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(session));
    given(session.getId()).willReturn(SESSION_ID);
    given(session.isAnalysisRequestable()).willReturn(true);
    given(drawingAssetRepository.findById(ASSET_ID)).willReturn(Optional.of(asset));
    given(asset.getDrawingSession()).willReturn(session);
    given(asset.getAssetType()).willReturn(DrawingAssetType.FINAL);
  }

  private DrawingAnalysis processingAnalysis() {
    DrawingAnalysis analysis =
        DrawingAnalysis.processing(
            session,
            asset,
            com.ssafy.b209.analysis.domain.DrawingAnalysisScope.FINAL,
            DrawingAnalysisType.OBJECT_DETECTION,
            "550e8400-e29b-41d4-a716-446655440000",
            REQUESTED_AT);
    ReflectionTestUtils.setField(analysis, "id", ANALYSIS_ID);
    return analysis;
  }

  private void assertError(Runnable invocation, Object expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
