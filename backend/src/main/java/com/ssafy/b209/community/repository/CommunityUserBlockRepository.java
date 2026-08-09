package com.ssafy.b209.community.repository;

/** 사용자별 차단 관계를 멱등하게 생성·삭제하는 저장소 경계다. */
public interface CommunityUserBlockRepository {

  /**
   * 차단 관계가 없을 때만 생성한다.
   *
   * @param blockerUserId 차단한 사용자 ID
   * @param blockedUserId 차단된 사용자 ID
   * @return 새 행이 생성됐으면 {@code true}
   */
  boolean insertIfAbsent(Long blockerUserId, Long blockedUserId);

  /**
   * 차단 관계가 있으면 삭제한다.
   *
   * @param blockerUserId 차단한 사용자 ID
   * @param blockedUserId 차단된 사용자 ID
   */
  void delete(Long blockerUserId, Long blockedUserId);
}
