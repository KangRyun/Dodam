package com.ssafy.b209.community.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** 게시글에서 제거된 첨부 이미지의 Storage 삭제 작업을 등록한다. */
@Repository
public class CommunityAttachmentDeletionRepository {

  private final JdbcTemplate jdbcTemplate;

  public CommunityAttachmentDeletionRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 첨부 원본을 비동기 삭제 대상으로 등록한다.
   *
   * @param storageKey 삭제할 Storage Key
   * @param fileId 첨부 Metadata 내부 ID
   */
  public void schedule(String storageKey, Long fileId) {
    jdbcTemplate.update(
        """
        insert into storage_deletion_jobs (storage_key, resource_type, resource_id)
        values (?, 'COMMUNITY_ATTACHMENT', ?)
        """,
        storageKey,
        fileId);
  }
}
