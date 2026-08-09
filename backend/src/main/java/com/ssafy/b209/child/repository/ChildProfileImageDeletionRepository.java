package com.ssafy.b209.child.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** 교체되거나 삭제된 아동 프로필 이미지의 Storage 삭제 작업을 등록한다. */
@Repository
public class ChildProfileImageDeletionRepository {

  private final JdbcTemplate jdbcTemplate;

  public ChildProfileImageDeletionRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 프로필 이미지 원본을 비동기 삭제 대상으로 등록한다.
   *
   * @param storageKey 삭제할 Storage Key
   * @param fileId 프로필 이미지 Metadata ID
   */
  public void schedule(String storageKey, Long fileId) {
    jdbcTemplate.update(
        """
        insert into storage_deletion_jobs (storage_key, resource_type, resource_id)
        values (?, 'CHILD_PROFILE_IMAGE', ?)
        """,
        storageKey,
        fileId);
  }
}
