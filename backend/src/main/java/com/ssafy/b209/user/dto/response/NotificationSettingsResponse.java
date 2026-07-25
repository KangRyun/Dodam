package com.ssafy.b209.user.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 사용자별 알림 수신 설정을 전달한다.
 *
 * <p>저장 위치는 {@code user_notification_settings} 이며, 행이 없는 사용자에게는 컬럼 DEFAULT와 동일한 값을 반환한다.
 *
 * @param analysisCompleted 분석 완료 알림 수신 여부
 * @param community 커뮤니티 알림 수신 여부
 * @param serviceNotice 서비스 공지 수신 여부
 * @param marketing 마케팅 알림 수신 여부
 */
@Schema(description = "사용자 알림 수신 설정")
public record NotificationSettingsResponse(
    @Schema(description = "분석 완료 알림 수신 여부", example = "true") boolean analysisCompleted,
    @Schema(description = "커뮤니티 알림 수신 여부", example = "true") boolean community,
    @Schema(description = "서비스 공지 수신 여부", example = "true") boolean serviceNotice,
    @Schema(description = "마케팅 알림 수신 여부", example = "false") boolean marketing) {

  /**
   * 알림 설정 행이 없는 사용자에게 반환할 기본값을 만든다.
   *
   * <p>값은 {@code user_notification_settings} 컬럼 DEFAULT(분석·커뮤니티·공지 수신, 마케팅 미수신)와 일치시켜, 행 생성 시점에 응답이
   * 달라지지 않게 한다.
   *
   * @return 컬럼 DEFAULT와 동일한 알림 설정
   */
  public static NotificationSettingsResponse defaults() {
    return new NotificationSettingsResponse(true, true, true, false);
  }
}
