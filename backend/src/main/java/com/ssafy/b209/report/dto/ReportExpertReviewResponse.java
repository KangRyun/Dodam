package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 전문가 검토 워크플로의 현재 상태를 반환한다.
 *
 * <p>전문가 검토 워크플로가 아직 구현되지 않아 기본값 {@code NOT_REQUESTED}·{@code false}만 반환한다.
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
