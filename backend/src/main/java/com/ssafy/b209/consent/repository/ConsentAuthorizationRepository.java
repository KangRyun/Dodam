package com.ssafy.b209.consent.repository;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** 아동 대상 동의를 기록하기 전에 인증 사용자와 아동의 연결 관계를 확인한다. */
@Repository
public class ConsentAuthorizationRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 보호자 관계 조회 저장소를 구성한다.
   *
   * @param jdbcTemplate 기존 관계 테이블을 조회할 JDBC Template
   */
  public ConsentAuthorizationRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 사용자가 지정 아동의 동의를 처리할 수 있는 연결 보호자인지 확인한다.
   *
   * @param guardianUserId 인증된 보호자 사용자 ID
   * @param childId 동의 대상 아동 ID
   * @return 보호자-아동 관계가 존재하면 {@code true}
   */
  public boolean hasGuardianChildRelation(Long guardianUserId, Long childId) {
    Boolean exists =
        jdbcTemplate.queryForObject(
            "select exists(select 1 from guardian_child_relations where guardian_user_id = ? and child_id = ?)",
            Boolean.class,
            guardianUserId,
            childId);
    return Boolean.TRUE.equals(exists);
  }

  /**
   * 보호자가 활성 필수 USER 약관에 이미 남긴 최신 동의가 모두 AGREE인지 확인한다.
   *
   * <p>USER 범위 필수 동의는 보호자 온보딩(USER 동의 등록) 시점에 이미 기록되므로, 아동 동의 등록에서는 이번 요청에 다시 요구하지 않고 보호자 계정의 기존
   * 이력으로 충족 여부를 판정한다.
   *
   * @param actorUserId 동의를 처리하는 인증 보호자 사용자 ID
   * @param now 활성·시행 판정 기준 시각
   * @return 모든 활성 필수 USER 약관의 최신 동의가 AGREE이면 {@code true}
   */
  public boolean hasRequiredUserConsents(Long actorUserId, LocalDateTime now) {
    return countUnsatisfiedRequiredUserConsents(actorUserId, now) == 0L;
  }

  /**
   * 보호자의 최신 동의가 AGREE가 아닌 활성 필수 USER 약관의 수를 센다.
   *
   * <p>네이티브 {@code not exists(...)}의 boolean 매핑 문제를 피하려 미충족 약관 수를 {@code count(*)}로 조회한다. 결과가
   * {@code 0}이면 모든 필수 USER 동의가 충족된 것이다.
   *
   * <p>USER 범위 동의는 {@code subject_child_id}가 {@code NULL}로 저장되고 보호자는 {@code actor_user_id}로 식별되므로,
   * 해당 보호자·NULL 아동 조합의 약관별 최신 이력을 기준으로 판정한다.
   *
   * @param actorUserId 동의를 처리하는 인증 보호자 사용자 ID
   * @param now 활성·시행 판정 기준 시각
   * @return 최신 동의가 AGREE가 아닌 필수·활성 USER 약관 수
   */
  private long countUnsatisfiedRequiredUserConsents(Long actorUserId, LocalDateTime now) {
    Long unsatisfied =
        jdbcTemplate.queryForObject(
            "select count(*) from consent_terms t "
                + "where t.is_required = true and t.is_active = true "
                + "and t.target_scope = 'USER' and t.effective_at <= ? "
                + "and not exists (select 1 from consent_records r "
                + "where r.consent_term_id = t.id and r.actor_user_id = ? "
                + "and r.subject_child_id is null "
                + "and r.recorded_at = (select max(r2.recorded_at) from consent_records r2 "
                + "where r2.consent_term_id = t.id and r2.actor_user_id = ? "
                + "and r2.subject_child_id is null) "
                + "and r.action = 'AGREE')",
            Long.class,
            Timestamp.valueOf(now),
            actorUserId,
            actorUserId);
    return unsatisfied == null ? 0L : unsatisfied;
  }
}
