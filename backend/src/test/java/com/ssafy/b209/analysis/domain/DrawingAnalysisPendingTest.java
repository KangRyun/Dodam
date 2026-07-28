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

  @Test
  void createsPendingFinalRetryLinkedToFailedAnalysis() {
    DrawingSession session = mock(DrawingSession.class);
    DrawingAsset originalAsset = mock(DrawingAsset.class);
    DrawingAsset latestAsset = mock(DrawingAsset.class);
    DrawingAnalysis source =
        DrawingAnalysis.pending(
            session,
            originalAsset,
            DrawingAnalysisType.ACTIVITY_REPORT,
            "original-completion-key",
            LocalDateTime.of(2026, 7, 23, 10, 30));
    source.failFinal(
        "OBSERVATION_GENERATION_FAILED",
        "Report generation failed",
        LocalDateTime.of(2026, 7, 23, 10, 31));

    DrawingAnalysis retry =
        DrawingAnalysis.pendingRetry(
            source, latestAsset, "report-regeneration-key", LocalDateTime.of(2026, 7, 23, 10, 32));

    assertThat(retry.getState()).isEqualTo(DrawingAnalysisState.PENDING);
    assertThat(retry.getTaskType()).isEqualTo(DrawingAnalysisType.ACTIVITY_REPORT);
    assertThat(retry.getRetryOfAnalysis()).isSameAs(source);
    assertThat(retry.getDrawingAsset()).isSameAs(latestAsset);
    assertThat(retry.getRequestId()).isEqualTo("report-regeneration-key");
  }
}
