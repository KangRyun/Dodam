package com.ssafy.b209.analysis.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class DrawingAnalysisFinalTransitionTest {

  private static final LocalDateTime REQUESTED_AT = LocalDateTime.of(2026, 7, 23, 10, 30);
  private static final LocalDateTime COMPLETED_AT = LocalDateTime.of(2026, 7, 23, 10, 31);

  @Test
  void transitionsPendingFinalAnalysisToSuccess() {
    DrawingAnalysis analysis = pending();

    analysis.succeedFinal(
        "mock-observation-generator", "1.0", new BigDecimal("0.80"), COMPLETED_AT);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.SUCCESS);
    assertThat(analysis.getModelName()).isEqualTo("mock-observation-generator");
    assertThat(analysis.getModelVersion()).isEqualTo("1.0");
    assertThat(analysis.getConfidence()).isEqualByComparingTo("0.80");
    assertThat(analysis.getCompletedAt()).isEqualTo(COMPLETED_AT);
    assertThat(analysis.isPending()).isFalse();
  }

  @Test
  void transitionsPendingFinalAnalysisToFailed() {
    DrawingAnalysis analysis = pending();

    analysis.failFinal("OBSERVATION_GENERATION_FAILED", "관찰 리포트 생성을 완료하지 못했습니다.", COMPLETED_AT);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.FAILED);
    assertThat(analysis.getErrorCode()).isEqualTo("OBSERVATION_GENERATION_FAILED");
    assertThat(analysis.getCompletedAt()).isEqualTo(COMPLETED_AT);
  }

  @Test
  void rejectsSecondFinalTransition() {
    DrawingAnalysis analysis = pending();
    analysis.succeedFinal("mock", "1.0", null, COMPLETED_AT);

    assertThatThrownBy(() -> analysis.succeedFinal("mock", "1.0", null, COMPLETED_AT))
        .isInstanceOf(IllegalStateException.class);
  }

  @Test
  void rejectsConfidenceOutOfRange() {
    DrawingAnalysis analysis = pending();

    assertThatThrownBy(
            () -> analysis.succeedFinal("mock", "1.0", new BigDecimal("1.5"), COMPLETED_AT))
        .isInstanceOf(IllegalArgumentException.class);
  }

  private DrawingAnalysis pending() {
    return DrawingAnalysis.pending(
        mock(DrawingSession.class),
        mock(DrawingAsset.class),
        DrawingAnalysisType.ACTIVITY_REPORT,
        "completion-key-1234",
        REQUESTED_AT);
  }
}
