package com.ssafy.b209.child.repository;

import java.time.LocalDateTime;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 아동 프로필 Soft Delete와 연관 Storage 파일 삭제 예약을 담당한다.
 *
 * <p>호출 Service의 Transaction에서 접근 가능한 아동을 잠근 후 상태 변경과 삭제 작업 생성을 원자적으로 수행한다.
 */
@Repository
public class ChildDeletionRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 아동 삭제 Query를 실행할 Repository를 생성한다.
   *
   * @param jdbcTemplate 아동·보호자 관계와 Storage 삭제 작업 Table 접근 도구
   */
  public ChildDeletionRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 요청 보호자에게 연결된 활성 아동을 쓰기 잠금으로 조회한다.
   *
   * @param guardianUserId 삭제 요청 보호자 사용자 ID
   * @param childId 삭제할 아동 ID
   * @return 접근 가능한 활성 아동이면 {@code true}
   */
  public boolean lockAccessibleChild(long guardianUserId, long childId) {
    return !jdbcTemplate
        .queryForList(
            """
            select child.id
              from children child
              join guardian_child_relations relation on relation.child_id = child.id
             where child.id = ?
               and relation.guardian_user_id = ?
               and child.profile_status = 'ACTIVE'
               and child.deleted_at is null
             for update
            """,
            Long.class,
            childId,
            guardianUserId)
        .isEmpty();
  }

  /**
   * 아동에 연결된 전체 보호자 수를 조회한다.
   *
   * @param childId 보호자 관계를 확인할 아동 ID
   * @return 연결된 보호자 수
   */
  public int countGuardians(long childId) {
    Integer count =
        jdbcTemplate.queryForObject(
            "select count(*) from guardian_child_relations where child_id = ?",
            Integer.class,
            childId);
    return count == null ? 0 : count;
  }

  /**
   * 아동 프로필을 삭제 상태로 전환한다.
   *
   * @param childId 삭제할 아동 ID
   * @param deletedAt 삭제 처리 시각
   */
  public void markDeleted(long childId, LocalDateTime deletedAt) {
    jdbcTemplate.update(
        """
        update children
           set profile_status = 'DELETED',
               deleted_at = ?,
               updated_at = ?
         where id = ?
        """,
        deletedAt,
        deletedAt,
        childId);
  }

  /**
   * 아동의 그림·대화 음성·리포트 파일을 비동기 삭제할 작업으로 등록한다.
   *
   * <p>원본 데이터 행은 감사와 복구 정책을 위해 이 시점에 직접 삭제하지 않는다.
   *
   * @param childId 삭제 대상 파일을 소유한 아동 ID
   */
  public void scheduleStorageDeletions(long childId) {
    jdbcTemplate.update(
        """
        insert into storage_deletion_jobs (storage_key, resource_type, resource_id)
        select asset.storage_key, 'DRAWING_ASSET', asset.id
          from drawing_assets asset
          join drawing_sessions session on session.id = asset.drawing_session_id
         where session.child_id = ?
        union all
        select message.audio_storage_key, 'CONVERSATION_AUDIO', message.id
          from conversation_messages message
          join conversation_sessions conversation on conversation.id = message.conversation_session_id
          join drawing_sessions session on session.id = conversation.drawing_session_id
         where session.child_id = ?
           and message.audio_storage_key is not null
        union all
        select report.pdf_storage_key, 'REPORT_PDF', report.id
          from reports report
          join drawing_sessions session on session.id = report.drawing_session_id
         where session.child_id = ?
           and report.pdf_storage_key is not null
        """,
        childId,
        childId,
        childId);
  }
}
