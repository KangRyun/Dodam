package com.ssafy.b209.analysis.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.AnalysisStatusResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisDetailResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class DrawingAnalysisQueryServiceTest {

  private static final long SESSION_ID = 10L;
  private static final long GUARDIAN_USER_ID = 41L;
  private static final long ASSET_ID = 20L;
  private static final long ANALYSIS_ID = 30L;
  private static final LocalDateTime REQUESTED_AT = LocalDateTime.parse("2026-07-22T05:00:00");
  private static final LocalDateTime PROCESSED_AT = LocalDateTime.parse("2026-07-22T05:00:01");

  @Mock private DrawingAnalysisRepository drawingAnalysisRepository;
  @Mock private DrawingSession session;
  @Mock private DrawingAsset asset;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private DrawingAnalysisQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingAnalysisQueryService(
            drawingAnalysisRepository, currentUserResolver, accessValidator);
  }

  @Test
  void listsAnalysisHistoryForAnAccessibleSession() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    DrawingAnalysis analysis = mock(DrawingAnalysis.class);
    given(analysis.getId()).willReturn(ANALYSIS_ID);
    given(analysis.getDrawingAsset()).willReturn(asset);
    given(asset.getId()).willReturn(ASSET_ID);
    given(analysis.getScope()).willReturn(DrawingAnalysisScope.FINAL);
    given(analysis.getTaskType()).willReturn(DrawingAnalysisType.OBJECT_DETECTION);
    given(analysis.getState()).willReturn(DrawingAnalysisState.SUCCESS);
    given(analysis.getRequestedAt()).willReturn(REQUESTED_AT);
    given(analysis.getCompletedAt()).willReturn(PROCESSED_AT);
    given(
            drawingAnalysisRepository.findAllByDrawingSessionIdOrderByRequestedAtDescIdDesc(
                SESSION_ID))
        .willReturn(List.of(analysis));

    var history = service.getDrawingAnalyses(SESSION_ID);

    assertThat(history).hasSize(1);
    assertThat(history.getFirst().drawingAnalysisId()).isEqualTo(ANALYSIS_ID);
    assertThat(history.getFirst().drawingAssetId()).isEqualTo(ASSET_ID);
    assertThat(history.getFirst().scope()).isEqualTo(DrawingAnalysisScope.FINAL);
    assertThat(history.getFirst().state()).isEqualTo(DrawingAnalysisState.SUCCESS);
  }

  @Test
  void rejectsUnownedSessionBeforeReadingAnalysis() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(
            new BusinessException(
                com.ssafy.b209.drawing.exception.DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
        .given(accessValidator)
        .requireDrawingSessionAccess(GUARDIAN_USER_ID, SESSION_ID);

    assertThatThrownBy(() -> service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(drawingAnalysisRepository);
  }

  @ParameterizedTest
  @EnumSource(
      value = DrawingAnalysisState.class,
      names = {"PENDING", "PROCESSING"})
  void returnsPendingAndProcessingWithoutResult(DrawingAnalysisState state) {
    DrawingAnalysis analysis = analysis(state);
    givenDetail(analysis);

    DrawingAnalysisDetailResponse response = service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID);

    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.valueOf(state.name()));
    assertThat(response.model()).isNull();
    assertThat(response.detections()).isEmpty();
    assertThat(response.processedAt()).isNull();
    assertThat(response.failure()).isNull();
  }

  @Test
  void returnsSuccessfulAnalysisAndDetections() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PROCESSING);
    analysis.succeed(
        "mock-drawing-detector",
        "1.0",
        List.of(detection("HOUSE", 0), detection("TREE", 1)),
        PROCESSED_AT);
    givenDetail(analysis);

    DrawingAnalysisDetailResponse response = service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID);

    assertThat(response.drawingAnalysisId()).isEqualTo(ANALYSIS_ID);
    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.drawingAssetId()).isEqualTo(ASSET_ID);
    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(response.model().name()).isEqualTo("mock-drawing-detector");
    assertThat(response.detections())
        .extracting(detection -> detection.label())
        .containsExactly("HOUSE", "TREE");
    assertThat(response.requestedAt()).isEqualTo(Instant.parse("2026-07-22T05:00:00Z"));
    assertThat(response.processedAt()).isEqualTo(Instant.parse("2026-07-22T05:00:01Z"));
    assertThat(response.failure()).isNull();
  }

  @Test
  void returnsSuccessfulAnalysisWithEmptyDetections() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PROCESSING);
    analysis.succeed("mock-drawing-detector", "1.0", List.of(), PROCESSED_AT);
    givenDetail(analysis);

    DrawingAnalysisDetailResponse response = service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID);

    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(response.detections()).isEmpty();
  }

  @Test
  void returnsFailedAnalysisAsNormalResultWithSafeFailure() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PROCESSING);
    analysis.fail("TIMEOUT", "내부 주소를 포함할 수 있는 저장 메시지", PROCESSED_AT);
    givenDetail(analysis);

    DrawingAnalysisDetailResponse response = service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID);

    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.FAILED);
    assertThat(response.model()).isNull();
    assertThat(response.detections()).isEmpty();
    assertThat(response.failure().code()).isEqualTo("AI_ANALYSIS_FAILED");
    assertThat(response.failure().message()).isEqualTo("그림 분석 처리에 실패했습니다.");
  }

  @Test
  void rejectsMissingOrMismatchedAnalysisWithoutRevealingExistence() {
    given(drawingAnalysisRepository.findDetailBySessionIdAndAnalysisId(SESSION_ID, ANALYSIS_ID))
        .willReturn(Optional.empty());

    assertError(
        () -> service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_FOUND);
  }

  @Test
  void rejectsStateAndStoredResultMismatch() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.SUCCESS);
    givenDetail(analysis);

    assertError(
        () -> service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_INCONSISTENT);
  }

  @Test
  void exposesPartialSuccessAsSucceededWhenItHasAValidResult() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PROCESSING);
    analysis.complete(
        DrawingAnalysisState.PARTIAL_SUCCESS,
        "mock-drawing-detector",
        "1.0",
        List.of(detection("HOUSE", 0)),
        PROCESSED_AT);
    givenDetail(analysis);

    DrawingAnalysisDetailResponse response = service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID);

    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(response.detections()).hasSize(1);
  }

  @Test
  void rejectsFailedAnalysisWithoutStoredFailureInformation() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.FAILED);
    givenDetail(analysis);

    assertError(
        () -> service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_INCONSISTENT);
  }

  @Test
  void rejectsProcessingAnalysisWithStoredResult() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PROCESSING);
    analysis.succeed("mock-drawing-detector", "1.0", List.of(detection("HOUSE", 0)), PROCESSED_AT);
    ReflectionTestUtils.setField(analysis, "state", DrawingAnalysisState.PROCESSING);
    givenDetail(analysis);

    assertError(
        () -> service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_INCONSISTENT);
  }

  @Test
  void returnsCanonicalSuccessAndNormalizesLegacyPixelCoordinates() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PROCESSING);
    DrawingDetectedObject detectedObject = detection("HOUSE", 0);
    ReflectionTestUtils.setField(detectedObject, "id", 40L);
    analysis.succeed("mock-drawing-detector", "1.0", List.of(detectedObject), PROCESSED_AT);
    given(asset.getWidthPx()).willReturn(1000);
    given(asset.getHeightPx()).willReturn(800);
    given(drawingAnalysisRepository.findDetailByAnalysisId(ANALYSIS_ID))
        .willReturn(Optional.of(analysis));
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);

    AnalysisStatusResponse response = service.getAnalysisStatus(ANALYSIS_ID);

    assertThat(response.analysisId()).isEqualTo(ANALYSIS_ID);
    assertThat(response.analysisType()).isEqualTo(DrawingAnalysisScope.FINAL);
    assertThat(response.analysisTaskType()).isEqualTo(DrawingAnalysisType.OBJECT_DETECTION);
    assertThat(response.analysisStatus()).isEqualTo(DrawingAnalysisState.SUCCESS);
    assertThat(response.detectedObjects()).hasSize(1);
    assertThat(response.detectedObjects().getFirst().detectedObjectId()).isEqualTo(40L);
    assertThat(response.detectedObjects().getFirst().boundingBox().x())
        .isEqualByComparingTo("0.120000");
    assertThat(response.detectedObjects().getFirst().boundingBox().height())
        .isEqualByComparingTo("0.650000");
  }

  @Test
  void preservesPartialSuccessInCanonicalStatusResponse() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PROCESSING);
    analysis.complete(
        DrawingAnalysisState.PARTIAL_SUCCESS,
        "mock-drawing-detector",
        "1.0",
        List.of(),
        PROCESSED_AT);
    given(drawingAnalysisRepository.findDetailByAnalysisId(ANALYSIS_ID))
        .willReturn(Optional.of(analysis));
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);

    AnalysisStatusResponse response = service.getAnalysisStatus(ANALYSIS_ID);

    assertThat(response.analysisStatus()).isEqualTo(DrawingAnalysisState.PARTIAL_SUCCESS);
  }

  @Test
  void validatesCanonicalAnalysisAccessUsingItsSession() {
    DrawingAnalysis analysis = mock(DrawingAnalysis.class);
    given(analysis.getDrawingSession()).willReturn(session);
    given(session.getId()).willReturn(SESSION_ID);
    given(drawingAnalysisRepository.findDetailByAnalysisId(ANALYSIS_ID))
        .willReturn(Optional.of(analysis));
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(
            new BusinessException(
                com.ssafy.b209.drawing.exception.DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
        .given(accessValidator)
        .requireDrawingSessionAccess(GUARDIAN_USER_ID, SESSION_ID);

    assertThatThrownBy(() -> service.getAnalysisStatus(ANALYSIS_ID))
        .isInstanceOf(BusinessException.class);
  }

  @Test
  void rejectsAnalysisWhoseAssetBelongsToAnotherSession() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PROCESSING);
    DrawingSession otherSession = org.mockito.Mockito.mock(DrawingSession.class);
    given(otherSession.getId()).willReturn(99L);
    given(asset.getDrawingSession()).willReturn(otherSession);
    givenDetail(analysis);

    assertError(
        () -> service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_INCONSISTENT);
  }

  private DrawingAnalysis analysis(DrawingAnalysisState state) {
    given(session.getId()).willReturn(SESSION_ID);
    given(asset.getId()).willReturn(ASSET_ID);
    given(asset.getDrawingSession()).willReturn(session);
    DrawingAnalysis analysis =
        DrawingAnalysis.processing(
            session,
            asset,
            DrawingAnalysisScope.FINAL,
            DrawingAnalysisType.OBJECT_DETECTION,
            "550e8400-e29b-41d4-a716-446655440000",
            REQUESTED_AT);
    ReflectionTestUtils.setField(analysis, "id", ANALYSIS_ID);
    ReflectionTestUtils.setField(analysis, "state", state);
    return analysis;
  }

  private DrawingDetectedObject detection(String label, int displayOrder) {
    return DrawingDetectedObject.detected(
        label,
        new BigDecimal("0.95"),
        new BigDecimal("120"),
        new BigDecimal("80"),
        new BigDecimal("640"),
        new BigDecimal("520"),
        displayOrder,
        "1.0",
        PROCESSED_AT);
  }

  private void givenDetail(DrawingAnalysis analysis) {
    given(drawingAnalysisRepository.findDetailBySessionIdAndAnalysisId(SESSION_ID, ANALYSIS_ID))
        .willReturn(Optional.of(analysis));
  }

  private void assertError(Runnable invocation, DrawingAnalysisErrorCode expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
