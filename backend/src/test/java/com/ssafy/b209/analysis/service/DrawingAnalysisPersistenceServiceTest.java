package com.ssafy.b209.analysis.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.BoundingBoxResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
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
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
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
  @Mock private DrawingSession session;
  @Mock private DrawingAsset asset;

  private DrawingAnalysisPersistenceService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingAnalysisPersistenceService(
            drawingSessionRepository, drawingAssetRepository, drawingAnalysisRepository);
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
    verify(drawingAnalysisRepository).saveAndFlush(any(DrawingAnalysis.class));
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
  void rejectsAssetFromAnotherSessionAndNonFinalAsset() {
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
  void storesDetectionsAndSuccessState() {
    DrawingAnalysis analysis = processingAnalysis();
    given(drawingAnalysisRepository.findByIdForUpdate(ANALYSIS_ID))
        .willReturn(Optional.of(analysis));

    DrawingAnalysis completed =
        service.complete(
            ANALYSIS_ID,
            "mock-drawing-detector",
            "1.0",
            List.of(
                new DrawingDetectionResponse(
                    "HOUSE",
                    new BigDecimal("0.95"),
                    new BoundingBoxResponse(
                        new BigDecimal("120"),
                        new BigDecimal("80"),
                        new BigDecimal("640"),
                        new BigDecimal("520")))),
            PROCESSED_AT);

    assertThat(completed.getState()).isEqualTo(DrawingAnalysisState.SUCCESS);
    assertThat(completed.getDetections()).hasSize(1);
    assertThat(completed.getDetections().getFirst().getDisplayOrder()).isZero();
    verify(drawingAnalysisRepository).flush();
  }

  @Test
  void preservesFailedAnalysisRow() {
    DrawingAnalysis analysis = processingAnalysis();
    given(drawingAnalysisRepository.findByIdForUpdate(ANALYSIS_ID))
        .willReturn(Optional.of(analysis));

    service.fail(ANALYSIS_ID, "TIMEOUT", "그림 분석 요청을 완료하지 못했습니다.", PROCESSED_AT);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.FAILED);
    assertThat(analysis.getErrorCode()).isEqualTo("TIMEOUT");
    verify(drawingAnalysisRepository).flush();
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
