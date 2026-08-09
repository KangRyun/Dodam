package com.ssafy.b209.consent.repository;

import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 버전별 append-only 동의 이력을 접근 범위와 조회 조건에 맞게 페이지로 조회한다.
 *
 * <p>사용자 대상 이력은 행위자 본인만, 아동 대상 이력은 현재 연결 보호자만 조회할 수 있도록 SQL 조회 범위를 제한한다.
 */
@Repository
public class ConsentHistoryRepository {

  private static final String SELECT_COLUMNS =
      """
      select cr.id as consent_record_id,
             ct.id as term_id,
             ct.term_code,
             ct.target_scope,
             ct.is_required,
             ct.version,
             ct.title,
             cr.subject_child_id,
             cr.action,
             cr.recorded_at
        from consent_records cr
        join consent_terms ct on ct.id = cr.consent_term_id
      """;

  private static final RowMapper<ConsentHistoryRow> ROW_MAPPER =
      (resultSet, rowNumber) ->
          new ConsentHistoryRow(
              resultSet.getLong("consent_record_id"),
              resultSet.getLong("term_id"),
              resultSet.getString("term_code"),
              ConsentTargetScope.valueOf(resultSet.getString("target_scope")),
              resultSet.getBoolean("is_required"),
              resultSet.getString("version"),
              resultSet.getString("title"),
              resultSet.getObject("subject_child_id", Long.class),
              ConsentAction.valueOf(resultSet.getString("action")),
              resultSet.getTimestamp("recorded_at").toLocalDateTime());

  private final NamedParameterJdbcTemplate jdbcTemplate;

  /**
   * 동의 이력 조회 저장소를 구성한다.
   *
   * @param jdbcTemplate 이름 기반 파라미터로 이력을 조회할 JDBC Template
   */
  public ConsentHistoryRepository(NamedParameterJdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 인증 사용자가 접근할 수 있는 동의 이력을 필터와 페이지 조건에 맞춰 조회한다.
   *
   * @param userId 인증 사용자 식별자
   * @param childId 특정 아동 필터, 전체 접근 가능 이력이면 {@code null}
   * @param termCode 약관 코드 필터
   * @param fromInclusive 기록 시각 하한
   * @param toExclusive 기록 시각 상한
   * @param page 0부터 시작하는 페이지
   * @param size 페이지 크기
   * @return 현재 페이지 이력과 전체 건수
   */
  public ConsentHistoryPage findAccessibleHistory(
      Long userId,
      Long childId,
      String termCode,
      LocalDateTime fromInclusive,
      LocalDateTime toExclusive,
      int page,
      int size) {
    Map<String, Object> parameters = new HashMap<>();
    parameters.put("userId", userId);
    String whereClause = accessCondition(childId, parameters);
    whereClause += optionalConditions(termCode, fromInclusive, toExclusive, parameters);

    Long totalElements =
        jdbcTemplate.queryForObject(
            "select count(*) from consent_records cr "
                + "join consent_terms ct on ct.id = cr.consent_term_id "
                + whereClause,
            parameters,
            Long.class);

    parameters.put("limit", size);
    parameters.put("offset", (long) page * size);
    var content =
        jdbcTemplate.query(
            SELECT_COLUMNS
                + whereClause
                + " order by cr.recorded_at desc, cr.id desc limit :limit offset :offset",
            parameters,
            ROW_MAPPER);
    return new ConsentHistoryPage(content, totalElements == null ? 0 : totalElements);
  }

  private String accessCondition(Long childId, Map<String, Object> parameters) {
    if (childId != null) {
      parameters.put("childId", childId);
      return " where cr.subject_child_id = :childId";
    }
    return """
     where ((cr.actor_user_id = :userId and cr.subject_child_id is null)
        or exists (
            select 1
              from guardian_child_relations gcr
             where gcr.guardian_user_id = :userId
               and gcr.child_id = cr.subject_child_id))
    """;
  }

  private String optionalConditions(
      String termCode,
      LocalDateTime fromInclusive,
      LocalDateTime toExclusive,
      Map<String, Object> parameters) {
    StringBuilder conditions = new StringBuilder();
    if (termCode != null) {
      conditions.append(" and ct.term_code = :termCode");
      parameters.put("termCode", termCode);
    }
    if (fromInclusive != null) {
      conditions.append(" and cr.recorded_at >= :fromInclusive");
      parameters.put("fromInclusive", Timestamp.valueOf(fromInclusive));
    }
    if (toExclusive != null) {
      conditions.append(" and cr.recorded_at < :toExclusive");
      parameters.put("toExclusive", Timestamp.valueOf(toExclusive));
    }
    return conditions.toString();
  }
}
