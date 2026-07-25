package com.ssafy.b209.user.repository;

/** 사용자 알림 수신 설정 조회 결과를 읽기 전용으로 전달한다. */
public interface UserNotificationSettingsProjection {

  /**
   * 분석 완료 알림 수신 여부를 반환한다.
   *
   * @return 수신하면 {@code true}
   */
  boolean getAnalysisCompleted();

  /**
   * 커뮤니티 알림 수신 여부를 반환한다.
   *
   * @return 수신하면 {@code true}
   */
  boolean getCommunity();

  /**
   * 서비스 공지 수신 여부를 반환한다.
   *
   * @return 수신하면 {@code true}
   */
  boolean getServiceNotice();

  /**
   * 마케팅 알림 수신 여부를 반환한다.
   *
   * @return 수신하면 {@code true}
   */
  boolean getMarketing();
}
