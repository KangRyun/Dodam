package com.ssafy.b209.analysis.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;

class DrawingAnalysisDomainTest {

  private static final LocalDateTime REQUESTED_AT = LocalDateTime.parse("2026-07-22T05:00:00");
  private static final LocalDateTime PROCESSED_AT = LocalDateTime.parse("2026-07-22T05:00:01");

  @Test
  void createsProcessingAnalysisAndCompletesWithDetections() {
    DrawingAnalysis analysis = processingAnalysis();
    DrawingDetectedObject detection =
        DrawingDetectedObject.detected(
            "HOUSE",
            new BigDecimal("0.95"),
            new BigDecimal("120.0"),
            new BigDecimal("80.0"),
            new BigDecimal("640.0"),
            new BigDecimal("520.0"),
            0,
            "1.0",
            PROCESSED_AT);

    analysis.succeed("mock-drawing-detector", "1.0", List.of(detection), PROCESSED_AT);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.SUCCESS);
    assertThat(analysis.getModelName()).isEqualTo("mock-drawing-detector");
    assertThat(analysis.getCompletedAt()).isEqualTo(PROCESSED_AT);
    assertThat(analysis.getDetections()).containsExactly(detection);
    assertThat(detection.getDrawingAnalysis()).isSameAs(analysis);
  }

  @Test
  void completesSuccessfullyWithNoDetections() {
    DrawingAnalysis analysis = processingAnalysis();

    analysis.succeed("mock-drawing-detector", "1.0", List.of(), PROCESSED_AT);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.SUCCESS);
    assertThat(analysis.getDetections()).isEmpty();
  }

  @Test
  void completesAsPartialSuccessWhenAiReportsUnusedInputs() {
    DrawingAnalysis analysis = processingAnalysis();

    analysis.complete(
        DrawingAnalysisState.PARTIAL_SUCCESS,
        "mock-drawing-detector",
        "1.0",
        List.of(),
        PROCESSED_AT);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.PARTIAL_SUCCESS);
    assertThat(analysis.getCompletedAt()).isEqualTo(PROCESSED_AT);
  }

  @Test
  void preservesSafeFailureInformation() {
    DrawingAnalysis analysis = processingAnalysis();

    analysis.fail("AI_TIMEOUT", "그림 분석 요청을 완료하지 못했습니다.", PROCESSED_AT);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.FAILED);
    assertThat(analysis.getErrorCode()).isEqualTo("AI_TIMEOUT");
    assertThat(analysis.getErrorMessage()).isEqualTo("그림 분석 요청을 완료하지 못했습니다.");
    assertThat(analysis.getCompletedAt()).isEqualTo(PROCESSED_AT);
  }

  @Test
  void rejectsStateChangeAfterAnalysisHasFinished() {
    DrawingAnalysis analysis = processingAnalysis();
    analysis.fail("AI_ERROR", "분석 실패", PROCESSED_AT);

    assertThatThrownBy(
            () ->
                analysis.succeed(
                    "mock-drawing-detector", "1.0", List.of(), PROCESSED_AT.plusSeconds(1)))
        .isInstanceOf(IllegalStateException.class);
  }

  @Test
  void rejectsInvalidDetectionValues() {
    assertThatThrownBy(
            () ->
                DrawingDetectedObject.detected(
                    "HOUSE",
                    new BigDecimal("1.01"),
                    BigDecimal.ZERO,
                    BigDecimal.ZERO,
                    BigDecimal.ONE,
                    BigDecimal.ONE,
                    0,
                    "1.0",
                    PROCESSED_AT))
        .isInstanceOf(IllegalArgumentException.class);

    assertThatThrownBy(
            () ->
                DrawingDetectedObject.detected(
                    "HOUSE",
                    new BigDecimal("0.5"),
                    new BigDecimal("-1"),
                    BigDecimal.ZERO,
                    BigDecimal.ZERO,
                    BigDecimal.ONE,
                    0,
                    "1.0",
                    PROCESSED_AT))
        .isInstanceOf(IllegalArgumentException.class);
  }

  private DrawingAnalysis processingAnalysis() {
    return DrawingAnalysis.processing(
        mock(DrawingSession.class),
        mock(DrawingAsset.class),
        DrawingAnalysisScope.FINAL,
        DrawingAnalysisType.OBJECT_DETECTION,
        "550e8400-e29b-41d4-a716-446655440000",
        REQUESTED_AT);
  }
}
