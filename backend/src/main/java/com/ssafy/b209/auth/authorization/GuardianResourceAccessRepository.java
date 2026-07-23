package com.ssafy.b209.auth.authorization;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** 보호자와 활성 아동·그림 활동의 연결 관계를 개인정보 조회 없이 확인한다. */
@Repository
public class GuardianResourceAccessRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 기존 보호자 관계와 그림 활동 Table을 조회하는 Repository를 생성한다.
   *
   * @param jdbcTemplate 관계 존재 여부 Query를 실행할 JDBC Template
   */
  public GuardianResourceAccessRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 보호자가 삭제되지 않은 활성 아동과 연결되어 있는지 확인한다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param childId 접근 대상 아동 식별자
   * @return 보호자 관계와 활성 아동이 모두 존재하면 {@code true}
   */
  public boolean hasChildAccess(Long guardianUserId, Long childId) {
    Boolean exists =
        jdbcTemplate.queryForObject(
            """
            select exists(
                select 1
                  from children child
                  join guardian_child_relations relation on relation.child_id = child.id
                 where relation.guardian_user_id = ?
                   and child.id = ?
                   and child.profile_status = 'ACTIVE'
                   and child.deleted_at is null
            )
            """,
            Boolean.class,
            guardianUserId,
            childId);
    return Boolean.TRUE.equals(exists);
  }

  /**
   * 보호자가 삭제되지 않은 활성 아동의 그림 활동에 접근할 수 있는지 확인한다.
   *
   * @param guardianUserId 인증된 보호자 사용자 식별자
   * @param drawingSessionId 접근 대상 그림 활동 식별자
   * @return 보호자 관계와 접근 가능한 아동·그림 활동이 모두 존재하면 {@code true}
   */
  public boolean hasDrawingSessionAccess(Long guardianUserId, Long drawingSessionId) {
    Boolean exists =
        jdbcTemplate.queryForObject(
            """
            select exists(
                select 1
                  from drawing_sessions session
                  join children child on child.id = session.child_id
                  join guardian_child_relations relation on relation.child_id = child.id
                 where relation.guardian_user_id = ?
                   and session.id = ?
                   and session.session_status <> 'DELETED'
                   and session.deleted_at is null
                   and child.profile_status = 'ACTIVE'
                   and child.deleted_at is null
            )
            """,
            Boolean.class,
            guardianUserId,
            drawingSessionId);
    return Boolean.TRUE.equals(exists);
  }
}
