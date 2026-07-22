package com.ssafy.b209.consent.repository;

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
}
