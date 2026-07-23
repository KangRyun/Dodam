package com.ssafy.b209.drawing.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 그림 활동에 연결된 Storage 파일의 비동기 삭제 작업을 등록한다.
 *
 * <p>그림 활동 Entity 상태 변경은 {@link DrawingSessionRepository}가 담당하며, 이 Repository는 물리 파일 정리에 필요한 작업 생성만
 * 담당한다.
 */
@Repository
public class DrawingSessionDeletionRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * Storage 삭제 작업 Table 접근 도구를 주입한다.
   *
   * @param jdbcTemplate 삭제 대상 파일을 조회하고 작업을 생성할 JDBC Template
   */
  public DrawingSessionDeletionRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 그림 활동의 그림·대화 음성·리포트 파일을 비동기 삭제할 작업으로 등록한다.
   *
   * @param drawingSessionId 삭제된 그림 활동 세션 ID
   */
  public void scheduleStorageDeletions(long drawingSessionId) {
    jdbcTemplate.update(
        """
        insert into storage_deletion_jobs (storage_key, resource_type, resource_id)
        select asset.storage_key, 'DRAWING_ASSET', asset.id
          from drawing_assets asset
         where asset.drawing_session_id = ?
        union all
        select message.audio_storage_key, 'CONVERSATION_AUDIO', message.id
          from conversation_messages message
          join conversation_sessions conversation on conversation.id = message.conversation_session_id
         where conversation.drawing_session_id = ?
           and message.audio_storage_key is not null
        union all
        select report.pdf_storage_key, 'REPORT_PDF', report.id
          from reports report
         where report.drawing_session_id = ?
           and report.pdf_storage_key is not null
        """,
        drawingSessionId,
        drawingSessionId,
        drawingSessionId);
  }
}
