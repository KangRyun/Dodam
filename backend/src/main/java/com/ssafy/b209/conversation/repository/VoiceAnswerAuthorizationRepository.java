package com.ssafy.b209.conversation.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** 음성 답변 저장 전에 보호자 관계·필수 동의·음성 처리 동의를 조회하는 경계다. */
@Repository
public class VoiceAnswerAuthorizationRepository {
  private static final String VOICE_PROCESSING_TERM_CODE = "VOICE_PROCESSING";
  private final JdbcTemplate jdbcTemplate;

  /**
   * 권한·동의 상태를 읽는 Repository를 생성한다.
   *
   * @param jdbcTemplate DB v1.2 관계·동의 이력 조회 도구
   */
  public VoiceAnswerAuthorizationRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 보호자가 활성 아동과 연결돼 있는지 확인한다.
   *
   * @param guardianUserId JWT Principal의 사용자 ID
   * @param childId 대화가 연결된 아동 ID
   * @return 연결된 활성 아동이면 {@code true}
   */
  public boolean hasGuardianChildRelation(Long guardianUserId, Long childId) {
    return exists(
        """
        select exists(
          select 1 from guardian_child_relations relation
          join children child on child.id = relation.child_id
          where relation.guardian_user_id = ? and child.id = ?
            and child.profile_status = 'ACTIVE' and child.deleted_at is null)
        """,
        guardianUserId,
        childId);
  }

  /**
   * 활성 필수 아동 약관({@code target_scope = 'CHILD'})이 모두 최신 AGREE 상태인지 확인한다.
   *
   * <p>보호자 본인 대상({@code USER}) 동의는 {@code subject_child_id}가 {@code null}로 기록되므로 아동 기준 대조에서 제외한다.
   * 포함하면 어떤 아동도 충족할 수 없다. {@code USER} 필수 동의는 동의 등록 시점에 강제된다.
   *
   * <p>{@code target_scope = 'CHILD'}로 아동 약관만 본다. USER-scope 약관(예: SERVICE_TOS)은 보호자 계정 동의라
   * {@code subject_child_id} 이력이 없어, 필터가 없으면 어떤 아동도 충족할 수 없어 음성 답변이 영구 차단된다.
   *
   * @param childId 동의 대상 아동 ID
   * @return 모든 활성 필수 아동 약관에 최신 동의가 있으면 {@code true}
   */
  public boolean hasRequiredConsents(Long childId) {
    return exists(
        """
        select not exists (
          select 1 from consent_terms term
          where term.is_required = true and term.is_active = true
            and term.target_scope = 'CHILD'
            and not exists (
              select 1 from consent_records record
              where record.consent_term_id = term.id and record.subject_child_id = ?
                and record.recorded_at = (
                  select max(latest.recorded_at) from consent_records latest
                  where latest.consent_term_id = term.id and latest.subject_child_id = ?)
                and record.action = 'AGREE'))
        """,
        childId,
        childId);
  }

  /**
   * 최신 활성 {@code VOICE_PROCESSING} 아동 약관이 AGREE 상태인지 확인한다.
   *
   * @param childId 음성 처리 동의 대상 아동 ID
   * @return 음성 처리 동의가 존재하고 철회되지 않았으면 {@code true}
   */
  public boolean hasVoiceProcessingConsent(Long childId) {
    return exists(
        """
        select exists (
          select 1 from consent_terms term
          where term.term_code = ? and term.target_scope = 'CHILD' and term.is_active = true
            and exists (
              select 1 from consent_records record
              where record.consent_term_id = term.id and record.subject_child_id = ?
                and record.recorded_at = (
                  select max(latest.recorded_at) from consent_records latest
                  where latest.consent_term_id = term.id and latest.subject_child_id = ?)
                and record.action = 'AGREE')
        )
        """,
        VOICE_PROCESSING_TERM_CODE,
        childId,
        childId);
  }

  private boolean exists(String sql, Object... arguments) {
    Boolean result = jdbcTemplate.queryForObject(sql, Boolean.class, arguments);
    return Boolean.TRUE.equals(result);
  }
}
