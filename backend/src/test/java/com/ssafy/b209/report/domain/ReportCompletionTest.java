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
    assertThat(report.getFailureReason()).isNull();
    assertThat(report.getFailedAt()).isNull();
  }

  @Test
  void failsGeneratingReport() {
    Report report = generating();

    report.fail("생성에 실패했습니다.", "TIMEOUT", UPDATED_AT);

    // 재시도 판단을 넘기지 않은 호출은 최종 실패로 남는다. 어느 쪽인지 모르는 실패를 대기열에
    //   올려 AI 를 반복 호출하는 것보다, 안 하는 쪽이 안전하다(P0-2).
    assertThat(report.getStatus()).isEqualTo(ReportStatus.FAILED_FINAL);
    assertThat(report.isExpertReviewRecommended()).isFalse();
    assertThat(report.getUpdatedAt()).isEqualTo(UPDATED_AT);
    assertThat(report.getFailureReason()).isEqualTo("TIMEOUT");
    assertThat(report.getFailedAt()).isEqualTo(UPDATED_AT);
  }

  /** 재시도 가능한 실패는 되돌려 다시 만들 수 있다 (P0-2). */
  @Test
  void reopensRetryableFailureAsGenerating() {
    Report report = generating();
    report.fail("생성에 실패했습니다.", "TIMEOUT", UPDATED_AT, ReportStatus.FAILED_RETRYABLE);

    report.reopenForRetry(UPDATED_AT.plusMinutes(5));

    assertThat(report.getStatus()).isEqualTo(ReportStatus.GENERATING);
    assertThat(report.getFailureReason()).isNull();
    assertThat(report.getFailedAt()).isNull();
    // ⚠️ limitations_text 는 DB 에서 NOT NULL 이다. 비우면 flush 에서 터진다.
    assertThat(report.getLimitationsText()).isNotBlank();
  }

  /** 다시 해도 같은 실패는 되돌리지 않는다. 옛 FAILED 도 어느 쪽인지 알 수 없어 되돌리지 않는다. */
  @Test
  void refusesToReopenNonRetryableFailure() {
    Report finalFailure = generating();
    finalFailure.fail("생성에 실패했습니다.", "INVALID_RESPONSE", UPDATED_AT);

    assertThatThrownBy(() -> finalFailure.reopenForRetry(UPDATED_AT))
        .isInstanceOf(IllegalStateException.class);
  }

  @Test
  void keepsFailureFieldsNullBeforeFailure() {
    Report report = generating();

    assertThat(report.getFailureReason()).isNull();
    assertThat(report.getFailedAt()).isNull();
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
