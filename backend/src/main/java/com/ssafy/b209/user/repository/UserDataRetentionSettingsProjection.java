package com.ssafy.b209.user.repository;

/** 사용자 데이터 보관 설정 조회 결과를 읽기 전용으로 전달한다. */
public interface UserDataRetentionSettingsProjection {

  /**
   * 데이터를 보관하는 기간을 반환한다.
   *
   * @return 보관 기간(일)
   */
  int getRetentionDays();

  /**
   * 보관 만료 사전 안내 시점을 반환한다.
   *
   * @return 만료 며칠 전에 안내하는지(일)
   */
  int getNoticeDaysBefore();
}
