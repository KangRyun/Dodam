package com.ssafy.b209.consent.repository;

import com.ssafy.b209.consent.domain.ConsentAction;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

/**
 * append-only 동의 이력에서 약관별 가장 최근 행위를 조회한다.
 *
 * <p>현재 상태를 별도로 저장하지 않으므로 약관마다 마지막 이력을 계산해 동의 여부를 판정한다.
 */
@Repository
public class ConsentStatusRepository {

  private static final RowMapper<LatestConsentAction> ROW_MAPPER =
      (resultSet, rowNumber) ->
          new LatestConsentAction(
              resultSet.getLong("consent_term_id"),
              ConsentAction.valueOf(resultSet.getString("action")),
              resultSet.getTimestamp("recorded_at").toLocalDateTime());

  private final JdbcTemplate jdbcTemplate;

  /**
   * 최신 동의 상태 조회 저장소를 구성한다.
   *
   * @param jdbcTemplate 동의 이력을 조회할 JDBC Template
   */
  public ConsentStatusRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 사용자 본인 대상 약관의 약관별 가장 최근 행위를 조회한다.
   *
   * @param actorUserId 조회할 사용자 식별자
   * @return 약관별 최신 사용자 동의 행위 목록
   */
  public List<LatestConsentAction> findLatestUserScopeActions(Long actorUserId) {
    return jdbcTemplate.query(
        """
        select cr.consent_term_id, cr.action, cr.recorded_at
          from consent_records cr
         where cr.actor_user_id = ?
           and cr.subject_child_id is null
           and cr.id = (
               select max(cr2.id)
                 from consent_records cr2
                where cr2.consent_term_id = cr.consent_term_id
                  and cr2.actor_user_id = ?
                  and cr2.subject_child_id is null)
        """,
        ROW_MAPPER,
        actorUserId,
        actorUserId);
  }

  /**
   * 아동 대상 약관의 약관별 가장 최근 행위를 조회한다.
   *
   * @param childId 조회할 아동 식별자
   * @return 약관별 최신 아동 동의 행위 목록
   */
  public List<LatestConsentAction> findLatestChildScopeActions(Long childId) {
    return jdbcTemplate.query(
        """
        select cr.consent_term_id, cr.action, cr.recorded_at
          from consent_records cr
         where cr.subject_child_id = ?
           and cr.id = (
               select max(cr2.id)
                 from consent_records cr2
                where cr2.consent_term_id = cr.consent_term_id
                  and cr2.subject_child_id = ?)
        """,
        ROW_MAPPER,
        childId,
        childId);
  }
}
