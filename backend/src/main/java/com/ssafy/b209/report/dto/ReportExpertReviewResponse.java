package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 전문가 검토 워크플로의 현재 상태를 반환한다.
 *
 * <p><b>사람 전문가 검토 워크플로는 존재하지 않으므로 항상 {@code NOT_REQUESTED}·{@code false}다.</b> 관찰 결과의 {@code
 * expertReviewRequired}(사람 상담 권유 신호)와 혼동하지 말 것 — 그 신호는 상담 권유 경로로 이어질 뿐 이 필드를 움직이지 않는다. 대기 중인 사람 검토가
 * 없는데 "검토 요청됨"으로 보이면 보호자가 오지 않을 결과를 기다린다.
 *
 * @param status 전문가 검토 상태
 * @param available 전문가 검토 결과 열람 가능 여부
 */
@Schema(description = "전문가 검토 상태")
public record ReportExpertReviewResponse(String status, boolean available) {

  private static final ReportExpertReviewResponse NOT_REQUESTED =
      new ReportExpertReviewResponse("NOT_REQUESTED", false);

  /**
   * 전문가 검토가 요청되지 않은 기본 상태를 반환한다.
   *
   * @return {@code NOT_REQUESTED}·열람 불가 기본 응답
   */
  public static ReportExpertReviewResponse notRequested() {
    return NOT_REQUESTED;
  }
}
