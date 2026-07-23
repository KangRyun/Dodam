package com.ssafy.b209.report.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.drawing.domain.DrawingSession;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class ReportCompletionTest {

  private static final LocalDateTime CREATED_AT = LocalDateTime.of(2026, 7, 23, 10, 30);
  private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2026, 7, 23, 10, 31);

  @Test
  void completesGeneratingReportWithLimitations() {
    Report report = generating();

    report.complete(true, "관찰 기록이며 발달 상태를 단정하지 않습니다.", UPDATED_AT);

    assertThat(report.getStatus()).isEqualTo(ReportStatus.COMPLETED);
    assertThat(report.isExpertReviewRecommended()).isTrue();
    assertThat(report.getLimitationsText()).contains("단정하지 않습니다");
    assertThat(report.getUpdatedAt()).isEqualTo(UPDATED_AT);
  }

  @Test
  void failsGeneratingReport() {
    Report report = generating();

    report.fail("생성에 실패했습니다.", UPDATED_AT);

    assertThat(report.getStatus()).isEqualTo(ReportStatus.FAILED);
    assertThat(report.isExpertReviewRecommended()).isFalse();
    assertThat(report.getUpdatedAt()).isEqualTo(UPDATED_AT);
  }

  @Test
  void rejectsCompletionWithBlankLimitations() {
    Report report = generating();

    assertThatThrownBy(() -> report.complete(false, "  ", UPDATED_AT))
        .isInstanceOf(IllegalArgumentException.class);
  }

  @Test
  void rejectsCompletingAlreadyCompletedReport() {
    Report report = generating();
    report.complete(false, "한계 문구", UPDATED_AT);

    assertThatThrownBy(() -> report.complete(false, "한계 문구", UPDATED_AT))
        .isInstanceOf(IllegalStateException.class);
  }

  private Report generating() {
    return Report.generating(
        mock(DrawingSession.class), mock(DrawingAnalysis.class), 1, CREATED_AT);
  }
}
