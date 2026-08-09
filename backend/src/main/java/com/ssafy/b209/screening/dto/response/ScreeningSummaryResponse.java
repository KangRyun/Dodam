package com.ssafy.b209.screening.dto.response;

import java.util.List;

/**
 * 리포트에 함께 싣는 선별 요약이다.
 *
 * <p><strong>제공 가능한 도구 목록을 내보내지 않는다.</strong> 승인 전 도구를 "곧 제공" 목록처럼 늘어놓으면 그 자체가 검사 권유로 읽힌다. 리포트가 말할
 * 수 있는 것은 두 가지뿐이다 — 지금 제공하는 선별검사가 없다는 사실과, 보호자가 직접 기록해 둔 결과가 있다는 사실.
 *
 * @param state 지금 상태이며 기록이 있으면 {@code EXTERNAL_RESULT_AVAILABLE}, 없으면 {@code NOT_OFFERED}
 * @param message 보호자에게 보이는 검토된 문구
 * @param records 보호자가 옮겨 적은 결과이며 없으면 빈 목록
 */
public record ScreeningSummaryResponse(
    String state, String message, List<ScreeningRecordResponse> records) {

  /** 목록은 빈 목록으로 정규화한다. */
  public ScreeningSummaryResponse {
    records = records == null ? List.of() : List.copyOf(records);
  }
}
