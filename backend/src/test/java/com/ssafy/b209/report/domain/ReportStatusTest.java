package com.ssafy.b209.report.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** 목록 필터가 보호자 눈에 보이는 표시와 같은 기준으로 묶이는지 고정한다. */
class ReportStatusTest {

  @Test
  @DisplayName("'다시 확인 필요'로 거르면 옛 실패와 최종 실패가 함께 나온다")
  void groupsGuardianVisibleFailures() {
    // 회귀: 실패가 셋으로 갈라진 뒤에도 필터가 정확히 한 값과만 맞춰 봐서,
    //   보호자가 봐야 할 FAILED_FINAL 리포트만 목록에서 통째로 빠졌다.
    assertThat(ReportStatus.visibleGroupOf(ReportStatus.FAILED))
        .containsExactlyInAnyOrder(ReportStatus.FAILED, ReportStatus.FAILED_FINAL);
    assertThat(ReportStatus.visibleGroupOf(ReportStatus.FAILED_FINAL))
        .containsExactlyInAnyOrder(ReportStatus.FAILED, ReportStatus.FAILED_FINAL);
  }

  @Test
  @DisplayName("재시도 대기 중인 실패는 '분석 중' 쪽에 묶인다")
  void groupsRetryableFailureWithGenerating() {
    // 재시도 작업이 아직 집어 갈 수 있어 보호자가 지금 할 일이 없다. 배지도 '분석 중'이다.
    assertThat(ReportStatus.visibleGroupOf(ReportStatus.GENERATING))
        .containsExactlyInAnyOrder(ReportStatus.GENERATING, ReportStatus.FAILED_RETRYABLE);
    assertThat(ReportStatus.visibleGroupOf(ReportStatus.FAILED_RETRYABLE))
        .containsExactlyInAnyOrder(ReportStatus.GENERATING, ReportStatus.FAILED_RETRYABLE);
  }

  @Test
  @DisplayName("고르지 않으면 전체를 넘겨 조건이 없는 것과 같게 둔다")
  void returnsEveryStatusWhenNotFiltered() {
    assertThat(ReportStatus.visibleGroupOf(null)).containsExactlyInAnyOrder(ReportStatus.values());
  }

  @Test
  @DisplayName("묶을 것이 없는 상태는 그 값만 넘긴다")
  void keepsStandaloneStatusesAlone() {
    assertThat(ReportStatus.visibleGroupOf(ReportStatus.COMPLETED))
        .containsExactly(ReportStatus.COMPLETED);
    assertThat(ReportStatus.visibleGroupOf(ReportStatus.HIDDEN))
        .containsExactly(ReportStatus.HIDDEN);
  }
}
