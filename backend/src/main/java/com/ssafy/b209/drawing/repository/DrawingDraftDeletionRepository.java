package com.ssafy.b209.drawing.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 그림 활동 초안 Metadata 삭제와 연결된 Storage 삭제 작업 등록을 함께 수행한다.
 *
 * <p>삭제 작업을 먼저 등록한 뒤 DRAFT Metadata를 제거하며, 호출 서비스의 Transaction이 실패하면 두 변경이 함께 Rollback된다.
 */
@Repository
public class DrawingDraftDeletionRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 초안 삭제 SQL을 실행할 JDBC Template을 주입한다.
   *
   * @param jdbcTemplate Storage 삭제 작업과 그림 파일 Metadata를 변경하는 JDBC Template
   */
  public DrawingDraftDeletionRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 세션의 모든 DRAFT 파일을 Storage 삭제 대상으로 등록하고 Metadata를 삭제한다.
   *
   * <p>INTERMEDIATE, FINAL과 Stroke 원본은 변경하지 않는다. DRAFT를 입력으로 사용한 임시 분석은 DB Foreign Key 정책에 따라 함께
   * 제거된다.
   *
   * @param drawingSessionId 초안을 삭제할 그림 활동 세션 ID
   * @return 삭제한 DRAFT Metadata 수
   */
  public int scheduleAndDeleteAll(long drawingSessionId) {
    jdbcTemplate.update(
        """
        insert into storage_deletion_jobs (storage_key, resource_type, resource_id)
        select asset.storage_key, 'DRAWING_ASSET', asset.id
          from drawing_assets asset
         where asset.drawing_session_id = ?
           and asset.asset_type = 'DRAFT'
        """,
        drawingSessionId);
    return jdbcTemplate.update(
        """
        delete from drawing_assets
         where drawing_session_id = ?
           and asset_type = 'DRAFT'
        """,
        drawingSessionId);
  }
}
