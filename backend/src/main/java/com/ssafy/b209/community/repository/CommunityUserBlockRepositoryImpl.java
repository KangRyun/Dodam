package com.ssafy.b209.community.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** MySQL 유일 제약과 {@code INSERT IGNORE}로 동시 차단 요청을 멱등 처리한다. */
@Repository
class CommunityUserBlockRepositoryImpl implements CommunityUserBlockRepository {

  private final JdbcTemplate jdbcTemplate;

  CommunityUserBlockRepositoryImpl(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  @Override
  public boolean insertIfAbsent(Long blockerUserId, Long blockedUserId) {
    return jdbcTemplate.update(
            "INSERT IGNORE INTO user_blocks (blocker_user_id, blocked_user_id) VALUES (?, ?)",
            blockerUserId,
            blockedUserId)
        == 1;
  }

  @Override
  public void delete(Long blockerUserId, Long blockedUserId) {
    jdbcTemplate.update(
        "DELETE FROM user_blocks WHERE blocker_user_id = ? AND blocked_user_id = ?",
        blockerUserId,
        blockedUserId);
  }
}
