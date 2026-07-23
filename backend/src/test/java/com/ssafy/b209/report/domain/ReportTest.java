package com.ssafy.b209.report.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.drawing.domain.DrawingSession;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class ReportTest {

  @Test
  void createsGeneratingReportWithoutPretendingContentIsComplete() {
    LocalDateTime createdAt = LocalDateTime.of(2026, 7, 23, 10, 30);

    Report report =
        Report.generating(mock(DrawingSession.class), mock(DrawingAnalysis.class), 1, createdAt);

    assertThat(report.getReportVersion()).isEqualTo(1);
    assertThat(report.getStatus()).isEqualTo(ReportStatus.GENERATING);
    assertThat(report.getPdfStatus()).isEqualTo(ReportPdfStatus.NONE);
    assertThat(report.isExpertReviewRecommended()).isFalse();
    assertThat(report.getLimitationsText()).contains("생성");
    assertThat(report.getCreatedAt()).isEqualTo(createdAt);
  }
}
