package com.ssafy.b209.consent.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.domain.ConsentRecord;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.domain.ConsentTerm;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@ActiveProfiles("test")
@Import(ConsentAuthorizationRepository.class)
class ConsentRepositoryTest {

  @Autowired private ConsentTermRepository termRepository;
  @Autowired private ConsentRecordRepository recordRepository;
  @Autowired private ConsentAuthorizationRepository authorizationRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void createGuardianRelationTable() {
    jdbcTemplate.execute(
        "create table if not exists guardian_child_relations (guardian_user_id bigint not null, child_id bigint not null)");
    jdbcTemplate.update("delete from guardian_child_relations");
  }

  @Test
  void storesVersionedTermAndAppendOnlyConsentRecord() {
    LocalDateTime now = LocalDateTime.of(2026, 7, 23, 0, 0);
    ConsentTerm term =
        termRepository.saveAndFlush(
            ConsentTerm.define(
                "SERVICE_TERMS",
                ConsentTargetScope.USER,
                true,
                "1.0",
                "서비스 이용약관",
                "https://example.com/terms/1.0",
                now.minusDays(1),
                true,
                now.minusDays(2)));

    ConsentRecord record =
        recordRepository.saveAndFlush(
            ConsentRecord.record(
                term,
                41L,
                null,
                "a".repeat(64),
                ConsentAction.AGREE,
                "127.0.0.1",
                "test-agent",
                now));

    assertThat(termRepository.findAllByActiveTrue()).containsExactly(term);
    assertThat(record.getId()).isPositive();
    assertThat(recordRepository.count()).isEqualTo(1);
  }

  @Test
  void confirmsRequiredUserConsentsFromActorLatestAgreeHistory() {
    LocalDateTime now = LocalDateTime.of(2026, 7, 23, 0, 0);
    ConsentTerm userRequired =
        termRepository.saveAndFlush(
            ConsentTerm.define(
                "SERVICE_TOS",
                ConsentTargetScope.USER,
                true,
                "1.0",
                "서비스 이용약관",
                null,
                now.minusDays(1),
                true,
                now.minusDays(2)));
    termRepository.saveAndFlush(
        ConsentTerm.define(
            "CHILD_PERSONAL_INFO",
            ConsentTargetScope.CHILD,
            true,
            "1.0",
            "아동 개인정보",
            null,
            now.minusDays(1),
            true,
            now.minusDays(2)));

    assertThat(authorizationRepository.hasRequiredUserConsents(41L, now)).isFalse();

    recordRepository.saveAndFlush(
        ConsentRecord.record(
            userRequired, 41L, null, "a".repeat(64), ConsentAction.AGREE, null, null, now));

    assertThat(authorizationRepository.hasRequiredUserConsents(41L, now)).isTrue();
    assertThat(authorizationRepository.hasRequiredUserConsents(42L, now)).isFalse();
  }

  @Test
  void treatsLatestUserWithdrawAsUnsatisfiedRequiredConsent() {
    LocalDateTime now = LocalDateTime.of(2026, 7, 23, 0, 0);
    ConsentTerm userRequired =
        termRepository.saveAndFlush(
            ConsentTerm.define(
                "SERVICE_TOS",
                ConsentTargetScope.USER,
                true,
                "1.0",
                "서비스 이용약관",
                null,
                now.minusDays(1),
                true,
                now.minusDays(2)));
    recordRepository.saveAndFlush(
        ConsentRecord.record(
            userRequired,
            41L,
            null,
            "a".repeat(64),
            ConsentAction.AGREE,
            null,
            null,
            now.minusHours(2)));
    recordRepository.saveAndFlush(
        ConsentRecord.record(
            userRequired,
            41L,
            null,
            "a".repeat(64),
            ConsentAction.WITHDRAW,
            null,
            null,
            now.minusHours(1)));

    assertThat(authorizationRepository.hasRequiredUserConsents(41L, now)).isFalse();
  }

  @Test
  void checksGuardianChildRelationWithoutExposingChildData() {
    jdbcTemplate.update(
        "insert into guardian_child_relations (guardian_user_id, child_id) values (?, ?)", 41L, 7L);

    assertThat(authorizationRepository.hasGuardianChildRelation(41L, 7L)).isTrue();
    assertThat(authorizationRepository.hasGuardianChildRelation(42L, 7L)).isFalse();
  }
}
