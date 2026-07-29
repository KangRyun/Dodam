package com.ssafy.b209.notification.repository;

import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 약관 변경 알림의 수신자를 개인정보 조회 없이 찾는다.
 *
 * <p>수신 대상은 변경된 약관 코드에 <b>현재 활성 동의를 보유한 사용자</b>다. 즉 append-only 동의 이력({@code consent_records})에서 해당
 * 약관 코드의 가장 최근 행위가 {@code AGREE}인 사용자만 재동의 안내 대상으로 본다. 명세·계약에 수신자 정의가 없어 이 기준을 기본값으로 채택했다(557
 * as-built §약관 변경 수신자 선정).
 *
 * <p>약관 코드는 버전마다 별도 {@code consent_terms} 행으로 존재하므로 최신 행위 판정은 버전({@code consent_term_id})·대상별로
 * 수행하고, 사용자 본인 약관과 아동 약관을 모두 포함한다. 아동 약관도 재동의는 보호자({@code actor_user_id})가 하므로 알림 수신자는 보호자 사용자 ID로
 * 통일한다.
 */
@Repository
public class TermsChangeRecipientRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 동의 이력 Query를 실행할 JDBC Template을 주입받는다.
   *
   * @param jdbcTemplate 동의 이력 조회용 JDBC Template
   */
  public TermsChangeRecipientRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 주어진 약관 코드에 활성 동의를 보유한 사용자 ID를 찾는다.
   *
   * <p>버전·대상별 마지막 행위가 {@code AGREE}인 이력만 남기고 그 행위를 수행한 사용자를 중복 없이 반환한다. 대상 사용자가 없으면 빈 목록을 반환한다.
   *
   * @param termCode 변경된 약관을 식별하는 안정적인 코드
   * @return 재동의 안내 대상 사용자 ID 목록이며 대상이 없으면 빈 목록
   */
  public List<Long> findActiveConsentUserIdsByTermCode(String termCode) {
    return jdbcTemplate.queryForList(
        """
        select distinct owner_user_id from (
            select cr.actor_user_id as owner_user_id
              from consent_records cr
              join consent_terms ct on ct.id = cr.consent_term_id
             where ct.term_code = ?
               and cr.actor_user_id is not null
               and cr.subject_child_id is null
               and cr.action = 'AGREE'
               and cr.id = (
                   select max(cr2.id)
                     from consent_records cr2
                    where cr2.consent_term_id = cr.consent_term_id
                      and cr2.actor_user_id = cr.actor_user_id
                      and cr2.subject_child_id is null)
            union
            select cr.actor_user_id as owner_user_id
              from consent_records cr
              join consent_terms ct on ct.id = cr.consent_term_id
             where ct.term_code = ?
               and cr.actor_user_id is not null
               and cr.subject_child_id is not null
               and cr.action = 'AGREE'
               and cr.id = (
                   select max(cr2.id)
                     from consent_records cr2
                    where cr2.consent_term_id = cr.consent_term_id
                      and cr2.subject_child_id = cr.subject_child_id)
        ) recipients
        """,
        Long.class,
        termCode,
        termCode);
  }
}
