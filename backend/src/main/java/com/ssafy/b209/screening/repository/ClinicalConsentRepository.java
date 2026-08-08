package com.ssafy.b209.screening.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 임상 기록 보관 동의가 실제로 남아 있는지 확인한다.
 *
 * <p>보호자가 "동의했다"고 보내는 값을 믿지 않고 <strong>동의 이력을 직접 확인한다.</strong> 요청 본문의 boolean 하나로 의료 기록 보관을 허용하면,
 * 나중에 무엇을 근거로 보관했는지 아무도 설명할 수 없다.
 */
@Repository
public class ClinicalConsentRepository {

  /** 아이의 검사·평가 기록 보관 동의 약관 코드다. */
  public static final String TERM_CODE = "CHILD_CLINICAL_RECORD";

  private final JdbcTemplate jdbcTemplate;

  /**
   * 동의 이력 조회 저장소를 구성한다.
   *
   * @param jdbcTemplate 동의 이력을 조회할 JDBC Template
   */
  public ClinicalConsentRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 이 동의 이력이 이 보호자·아동의 임상 기록 보관 동의인지 확인한다.
   *
   * <p>세 가지를 함께 본다 — <strong>같은 보호자·같은 아동·동의(AGREE) 행위.</strong> 하나라도 어긋나면 남의 동의로 남의 아이 기록을 남기는 셈이
   * 된다.
   *
   * @param consentRecordId 클라이언트가 제시한 동의 이력 식별자
   * @param actorUserId 인증된 보호자 사용자 식별자
   * @param childId 대상 아동 식별자
   * @return 유효한 동의 이력이면 {@code true}
   */
  public boolean isAgreedClinicalConsent(Long consentRecordId, Long actorUserId, Long childId) {
    Boolean exists =
        jdbcTemplate.queryForObject(
            """
            select exists(
                select 1
                  from consent_records record
                  join consent_terms term on term.id = record.consent_term_id
                 where record.id = ?
                   and record.actor_user_id = ?
                   and record.subject_child_id = ?
                   and record.action = 'AGREE'
                   and term.term_code = ?
            )
            """,
            Boolean.class,
            consentRecordId,
            actorUserId,
            childId,
            TERM_CODE);
    return Boolean.TRUE.equals(exists);
  }
}
