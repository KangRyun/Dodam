package com.ssafy.b209.child.repository;

import java.time.LocalDateTime;
import java.util.List;
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
        union all
        select profile.storage_key, 'CHILD_PROFILE_IMAGE', profile.id
          from child_profile_image_files profile
         where profile.child_id = ?
        """,
        childId,
        childId,
        childId,
        childId);
  }

  /**
   * 보호자가 <b>혼자</b> 보유한 아동 ID를 모두 찾는다 (S15P11B209-728).
   *
   * <p>회원 탈퇴 시 쓴다. 공동 보호자가 있는 아동은 제외한다 — 한 사람이 나간다고 다른 보호자의 아동 데이터를 지울 수는 없다. 그런 아동은 {@code
   * guardian_child_relations}의 CASCADE로 <b>관계만</b> 끊기고 레코드는 남는 것이 옳다.
   *
   * <p>이미 삭제된 아동({@code profile_status = 'DELETED'})은 제외한다. 다시 큐에 넣으면 스토리지 삭제 작업이 중복된다.
   *
   * @param guardianUserId 탈퇴하는 보호자 사용자 ID
   * @return 이 보호자만 보유한 활성 아동 ID 목록. 없으면 빈 목록
   */
  public List<Long> findSolelyOwnedChildIds(long guardianUserId) {
    return jdbcTemplate.queryForList(
        """
        select child.id
          from children child
          join guardian_child_relations relation on relation.child_id = child.id
         where relation.guardian_user_id = ?
           and child.profile_status = 'ACTIVE'
           and child.deleted_at is null
           and (select count(*)
                  from guardian_child_relations other
                 where other.child_id = child.id) = 1
        """,
        Long.class,
        guardianUserId);
  }

  /**
   * 탈퇴하는 사용자의 전문가 프로필을 삭제한다 (S15P11B209-728).
   *
   * <p>{@code expert_profiles.user_id}가 {@code ON DELETE RESTRICT}라, 남겨둔 채 사용자를 지우면 DB 제약 위반이 500으로
   * 새어 나간다. 사용자보다 <b>먼저</b> 지운다.
   *
   * <p>딸려 나가는 것(전부 {@code ON DELETE CASCADE}): 전문가 팔로우 · 전문 분야 · 자격 증빙과 그 첨부 파일. 미술 활동 자료({@code
   * activity_templates})는 <b>남는다</b> — V22 에서 {@code ON DELETE SET NULL}로 바꿔, 자료는 보존하고 작성자 참조만 끊는다.
   * 보호자에게 제공되는 콘텐츠라 작성자가 떠났다고 사라지면 안 된다.
   *
   * <p>⚠️ 컬럼명은 {@code user_id}다. V1 스키마에서는 {@code users_id}였으나 <b>V3에서 이름이 바뀌었다</b> ({@code RENAME
   * COLUMN users_id TO user_id}). V1만 보고 쓰면 {@code BadSqlGrammarException}이 나고, 탈퇴 API가 500으로 죽는다 —
   * 2026-07-30 실제로 그렇게 한 번 틀렸다. 스키마는 <b>마이그레이션 체인의 최종 상태</b>를 봐야 한다.
   *
   * @param userId 탈퇴하는 사용자 ID
   * @return 삭제한 프로필 수(0 또는 1). 전문가가 아니면 0
   */
  public int deleteExpertProfile(long userId) {
    return jdbcTemplate.update("delete from expert_profiles where user_id = ?", userId);
  }
}
