package com.ssafy.b209.analysis.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class DrawingAnalysisPendingTest {

  @Test
  void createsPendingFinalAnalysisWithoutStartingExternalProcessing() {
    LocalDateTime requestedAt = LocalDateTime.of(2026, 7, 23, 10, 30);

    DrawingAnalysis analysis =
        DrawingAnalysis.pending(
            mock(DrawingSession.class),
            mock(DrawingAsset.class),
            DrawingAnalysisType.ACTIVITY_REPORT,
            "completion-key",
            requestedAt);

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.PENDING);
    assertThat(analysis.getTaskType()).isEqualTo(DrawingAnalysisType.ACTIVITY_REPORT);
    assertThat(analysis.getRequestId()).isEqualTo("completion-key");
    assertThat(analysis.getRequestedAt()).isEqualTo(requestedAt);
    assertThat(analysis.getStartedAt()).isNull();
    assertThat(analysis.getCompletedAt()).isNull();
  }
}
