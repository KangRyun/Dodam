package com.ssafy.b209.consent.dto.response;

import java.util.List;

/**
 * 사용자 본인과 선택한 아동에 대한 현재 동의 현황이다.
 *
 * @param childId 아동 대상 현황을 함께 조회한 경우의 아동 식별자, 사용자 약관만 조회하면 {@code null}
 * @param requiredConsentsSatisfied 적용 범위의 모든 필수 약관에 동의했는지 여부
 * @param items 적용 약관별 현재 동의 상태 목록
 */
public record ConsentStatusResponse(
    Long childId, boolean requiredConsentsSatisfied, List<ConsentStatusItemResponse> items) {

  /** 항목 목록을 외부에서 변경할 수 없도록 복사한다. */
  public ConsentStatusResponse {
    items = List.copyOf(items);
  }
}
