package com.ssafy.b209.analysis.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.DrawingAnalysisDetailResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
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
  private static final long ASSET_ID = 20L;
  private static final long ANALYSIS_ID = 30L;
  private static final LocalDateTime REQUESTED_AT = LocalDateTime.parse("2026-07-22T05:00:00");
  private static final LocalDateTime PROCESSED_AT = LocalDateTime.parse("2026-07-22T05:00:01");

  @Mock private DrawingAnalysisRepository drawingAnalysisRepository;
  @Mock private DrawingSession session;
  @Mock private DrawingAsset asset;

  private DrawingAnalysisQueryService service;

  @BeforeEach
  void setUp() {
    service = new DrawingAnalysisQueryService(drawingAnalysisRepository);
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
  void rejectsPartialSuccessBecauseItHasNoPublicContract() {
    DrawingAnalysis analysis = analysis(DrawingAnalysisState.PARTIAL_SUCCESS);
    givenDetail(analysis);

    assertError(
        () -> service.getDrawingAnalysis(SESSION_ID, ANALYSIS_ID),
        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_INCONSISTENT);
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
