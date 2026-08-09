package com.ssafy.b209.notification.repository;

import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** 리포트가 속한 활성 아동의 보호자를 개인정보 조회 없이 찾아 분석 완료 알림 수신자를 해석한다. */
@Repository
public class AnalysisCompletedRecipientRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 보호자 관계 Query를 실행할 JDBC Template을 주입받는다.
   *
   * @param jdbcTemplate 관계 조회용 JDBC Template
   */
  public AnalysisCompletedRecipientRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 리포트 → 그림 활동 → 활성 아동 → 보호자 경로로 수신 대상 보호자 사용자 ID를 찾는다.
   *
   * <p>삭제됐거나 비활성인 아동은 제외한다. 한 아동에 보호자가 여러 명이면 모두 반환한다.
   *
   * @param reportId 완료된 리포트 식별자
   * @return 수신 대상 보호자 사용자 ID 목록이며 대상이 없으면 빈 목록
   */
  public List<Long> findGuardianUserIdsByReportId(Long reportId) {
    return jdbcTemplate.queryForList(
        """
        select relation.guardian_user_id
          from reports report
          join drawing_sessions session on session.id = report.drawing_session_id
          join children child on child.id = session.child_id
          join guardian_child_relations relation on relation.child_id = child.id
         where report.id = ?
           and child.profile_status = 'ACTIVE'
           and child.deleted_at is null
        """,
        Long.class,
        reportId);
  }
}
