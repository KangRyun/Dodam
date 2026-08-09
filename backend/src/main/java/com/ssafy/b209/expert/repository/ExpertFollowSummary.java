package com.ssafy.b209.expert.repository;

/** 전문가 목록·상세 응답에 필요한 팔로우 집계 Projection이다. */
public interface ExpertFollowSummary {

  /**
   * @return 전문가 프로필 식별자
   */
  Long getExpertId();

  /**
   * @return 현재 팔로워 수
   */
  long getFollowerCount();

  /**
   * @return 현재 사용자가 팔로우 중이면 {@code 1}, 아니면 {@code 0}
   */
  int getFollowedByMe();
}
