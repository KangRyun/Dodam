package com.ssafy.b209.user.repository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.user.domain.UserGuardianPin;
import java.time.LocalDateTime;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * {@link UserGuardianPinRepository} 와 V35 Migration 을 실 MySQL 로 검증한다 (S15P11B209-879).
 *
 * <p>단위 테스트로는 못 잡는 것을 본다: 엔티티 매핑이 실제 DDL 과 맞는지, {@code user_id} PK 가 계정당 PIN 하나를 강제하는지, {@code
 * users} 삭제 시 CASCADE 로 함께 지워지는지, CHECK 제약이 음수 카운터를 막는지, {@code findByUserIdForUpdate} 의 {@code for
 * update} 문법이 MySQL 에서 실행되는지. H2 로는 MySQL DDL 을 돌릴 수 없어 이 검증을 대신할 수 없다.
 */
@Testcontainers
@SpringBootTest
@ActiveProfiles("integration-test")
class UserGuardianPinRepositoryIntegrationTest {

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_guardian_pin")
          .withUsername("test")
          .withPassword("test");

  private static final LocalDateTime NOW = LocalDateTime.of(2026, 8, 4, 4, 0);

  @Autowired private UserGuardianPinRepository repository;
  @Autowired private JdbcTemplate jdbcTemplate;

  private Long userId;

  @BeforeEach
  void setUp() {
    jdbcTemplate.update("delete from user_guardian_pins");
    jdbcTemplate.update("delete from users");
    userId = insertGuardian();
  }

  @Test
  void savesAndReadsPinThroughRealSchema() {
    repository.saveAndFlush(
        UserGuardianPin.create(userId, "hash-value", "HMAC_SHA256+BCRYPT", NOW));

    UserGuardianPin found = repository.findById(userId).orElseThrow();

    assertThat(found.getPinHash()).isEqualTo("hash-value");
    assertThat(found.getHashAlgorithm()).isEqualTo("HMAC_SHA256+BCRYPT");
    assertThat(found.getFailedAttemptCount()).isZero();
    assertThat(found.getLockoutLevel()).isZero();
    assertThat(found.getLockedUntil()).isNull();
    // DB DEFAULT 로 채워지는 컬럼도 읽히는지 본다(insertable=false 매핑 확인).
    assertThat(found.getUpdatedAt()).isNotNull();
  }

  @Test
  void keepsOnlyOnePinPerGuardianAccount() {
    // user_id 가 PK 라 계정당 PIN 하나가 구조로 보장된다. 두 번째 INSERT 는 DB 가 막는다.
    repository.saveAndFlush(UserGuardianPin.create(userId, "first", "ALG", NOW));

    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    """
                    insert into user_guardian_pins (user_id, pin_hash, hash_algorithm)
                    values (?, ?, ?)
                    """,
                    userId,
                    "second",
                    "ALG"))
        .isInstanceOf(DataIntegrityViolationException.class);
  }

  @Test
  void persistsLockoutStateAcrossReload() {
    UserGuardianPin pin = UserGuardianPin.create(userId, "hash", "ALG", NOW);
    for (int attempt = 1; attempt <= UserGuardianPin.MAX_ATTEMPTS; attempt++) {
      pin.recordFailure(NOW);
    }
    repository.saveAndFlush(pin);

    // 잠금은 재기동·재조회 뒤에도 살아 있어야 한다. Redis 가 아니라 DB 를 권위 저장소로 둔 이유다.
    UserGuardianPin reloaded = repository.findById(userId).orElseThrow();
    assertThat(reloaded.getLockedUntil()).isEqualTo(NOW.plusSeconds(30));
    assertThat(reloaded.getLockoutLevel()).isEqualTo(1);
    assertThat(reloaded.isLocked(NOW.plusSeconds(10))).isTrue();
    assertThat(reloaded.isLocked(NOW.plusSeconds(31))).isFalse();
  }

  @Test
  @org.springframework.transaction.annotation.Transactional
  void locksRowWithForUpdateQuery() {
    // for update 문법이 MySQL 에서 실행되는지 본다. 실패하면 검증 경로가 런타임에 전부 깨진다.
    repository.saveAndFlush(UserGuardianPin.create(userId, "hash", "ALG", NOW));

    assertThat(repository.findByUserIdForUpdate(userId)).isPresent();
    assertThat(repository.findByUserIdForUpdate(userId + 9999)).isEmpty();
  }

  @Test
  void removesPinWhenGuardianAccountIsDeleted() {
    // 탈퇴 시 PIN 이 남으면 같은 user_id 가 재사용될 때 낯선 PIN 이 붙는다. FK CASCADE 로 지운다.
    repository.saveAndFlush(UserGuardianPin.create(userId, "hash", "ALG", NOW));

    jdbcTemplate.update("delete from users where id = ?", userId);

    assertThat(repository.findById(userId)).isEmpty();
  }

  @Test
  void rejectsNegativeCounters() {
    repository.saveAndFlush(UserGuardianPin.create(userId, "hash", "ALG", NOW));

    String constraints =
        String.join(
            ",",
            jdbcTemplate.queryForList(
                """
                select constraint_name from information_schema.table_constraints
                 where table_name = 'user_guardian_pins'
                """,
                String.class));
    assertThat(constraints).contains("ck_user_guardian_pins_counters");

    // MySQL 은 CHECK 위반을 error 3819(HY000)로 낸다. Spring 이 그 코드를 번역하지 않아
    // DataIntegrityViolationException 이 아니라 UncategorizedSQLException 으로 올라온다 — 상위 타입으로 받고
    // 메시지로 제약 이름을 확인한다.
    assertThatThrownBy(
            () ->
                jdbcTemplate.update(
                    "update user_guardian_pins set failed_attempt_count = -1 where user_id = ?",
                    userId))
        .isInstanceOf(DataAccessException.class)
        .hasMessageContaining("ck_user_guardian_pins_counters");
  }

  private Long insertGuardian() {
    jdbcTemplate.update(
        """
        insert into users (role, nickname, account_status, is_completed)
        values ('GUARDIAN', '보호자', 'ACTIVE', true)
        """);
    Map<String, Object> row =
        jdbcTemplate.queryForMap("select id from users order by id desc limit 1");
    return ((Number) row.get("id")).longValue();
  }
}
