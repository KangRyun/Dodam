package com.ssafy.b209.user.service;

import static java.time.temporal.ChronoUnit.MILLIS;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.support.IntegrationTestSupport;
import com.ssafy.b209.user.domain.UserGuardianPin;
import com.ssafy.b209.user.dto.response.GuardianPinStatusResponse;
import com.ssafy.b209.user.exception.GuardianPinErrorCode;
import com.ssafy.b209.user.exception.GuardianPinException;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 보호자 PIN 실패 기록이 <b>요청(트랜잭션) 경계를 넘어 실제로 커밋되는지</b>를 실 MySQL 로 고정한다 (S15P11B209-879).
 *
 * <p><b>왜 이 클래스가 따로 필요한가.</b> {@code GuardianPinServiceTest} 는 {@code MockitoExtension} + Mock
 * Repository 라 트랜잭션 경계가 없고, {@code findByUserIdForUpdate} 가 매 호출 <b>같은 엔티티 인스턴스</b>를 돌려주므로 실패 횟수가
 * in-memory 로 누적돼 초록이 된다. {@code UserGuardianPinRepositoryIntegrationTest} 는 Repository 계층만 보고 서비스의
 * 예외 경로를 지나지 않는다. 그래서 두 테스트 모두 통과하는 동안 "실패를 flush 한 뒤 {@code GuardianPinException}(= {@code
 * RuntimeException}) 을 던져 그 UPDATE 까지 함께 롤백되는" 결함이 살아 있었다 — {@code failed_attempt_count} 가 요청 사이에
 * 누적되지 않아 5회 잠금·지수 백오프가 영구히 동작하지 않고 응답 {@code remainingAttempts} 가 항상 4로 고정됐다.
 *
 * <p><b>⚠️ 이 클래스에 {@code @Transactional} 을 붙이면 안 된다.</b> 붙이면 서비스 호출이 테스트 트랜잭션에 참여해 커밋·롤백 경계가 사라지고,
 * 위 결함을 다시 잡지 못한다. 서비스를 직접 호출해 호출마다 자기 트랜잭션을 열고 닫게 하고, 결과 확인은 {@link JdbcTemplate} 의 새 읽기(또는 서비스의 별
 * 트랜잭션 조회)로만 한다.
 *
 * <p>{@code pepper} 를 주입하지 않으면 {@code GuardianPinHasher#isConfigured} 가 false 라 모든 호출이 {@code
 * PIN_UNAVAILABLE}(503) 로 끝나 아무것도 검증되지 않는다. BCrypt 강도는 보안 요구가 아니라 비용 설정이라 낮춰도 규칙 검증에 영향이 없다.
 */
@AutoConfigureMockMvc
class GuardianPinServiceIntegrationTest extends IntegrationTestSupport {

  private static final Long USER_ID = 41L;
  private static final String PIN = "1234";
  private static final String WRONG_PIN = "9999";
  private static final String NEW_PIN = "5678";

  /** 첫 잠금 시간. {@code UserGuardianPin} 의 백오프 1단계 값이다. */
  private static final long FIRST_LOCK_SECONDS = 30L;

  @Autowired private GuardianPinService guardianPinService;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private MockMvc mockMvc;

  @DynamicPropertySource
  static void guardianPinProperties(DynamicPropertyRegistry registry) {
    registry.add("app.security.guardian-pin.pepper", () -> "integration-test-pepper");
    registry.add("app.security.guardian-pin.hash-strength", () -> 4);
  }

  @BeforeEach
  void setUp() {
    setAuthenticatedUser(USER_ID);
    jdbcTemplate.update(
        """
        insert into users (id, role, nickname, account_status, is_completed)
        values (?, 'GUARDIAN', '보호자', 'ACTIVE', true)
        """,
        USER_ID);
    // 설정도 자기 트랜잭션에서 커밋돼야 뒤 단계가 성립한다.
    guardianPinService.configure(USER_ID, PIN);
    assertThat(failedAttemptCount()).isZero();
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void countsEveryVerifyFailureInItsOwnTransactionUntilLockout() {
    for (int attempt = 1; attempt < UserGuardianPin.MAX_ATTEMPTS; attempt++) {
      GuardianPinStatusResponse status = verifyFails(GuardianPinErrorCode.PIN_MISMATCH, WRONG_PIN);

      // 결함이 있으면 remainingAttempts 는 회차와 무관하게 4 로 고정되고, failed_attempt_count 는
      // UPDATE 가 롤백돼 0 에 머문다(실측: 1회차에서 expected 1 / but was 0).
      assertThat(status.remainingAttempts()).isEqualTo(UserGuardianPin.MAX_ATTEMPTS - attempt);
      assertThat(failedAttemptCount()).isEqualTo(attempt);
      assertThat(status.locked()).isFalse();
      assertThat(status.retryAfterSeconds()).isNull();
      assertThat(lockoutLevel()).isZero();
      assertThat(lockedUntil()).isNull();
    }

    LocalDateTime beforeLastAttempt = utcNow();
    GuardianPinStatusResponse locked = verifyFails(GuardianPinErrorCode.PIN_LOCKED, WRONG_PIN);
    LocalDateTime afterLastAttempt = utcNow();

    assertThat(locked.locked()).isTrue();
    assertThat(locked.remainingAttempts()).isZero();
    assertThat(locked.retryAfterSeconds()).isBetween(1L, FIRST_LOCK_SECONDS);
    // recordFailure 는 상한에 닿으면 카운터를 0으로 되돌리고 단계를 올린다(UserGuardianPin#recordFailure).
    // 잠금이 풀린 뒤 다시 MAX_ATTEMPTS 번의 기회를 주기 위한 동작이므로 0이 정상이다.
    assertThat(failedAttemptCount()).isZero();
    assertThat(lockoutLevel()).isEqualTo(1);
    assertThat(lockedUntil())
        .isAfterOrEqualTo(beforeLastAttempt.plusSeconds(FIRST_LOCK_SECONDS))
        .isBeforeOrEqualTo(afterLastAttempt.plusSeconds(FIRST_LOCK_SECONDS));
    // 응답이 커밋된 행과 같은 값을 말하는지 — 응답만 맞고 DB 가 비는 경우를 배제한다.
    assertThat(locked.lockedUntil()).isCloseTo(committedLockedUntil(), within(1, MILLIS));
  }

  @Test
  void keepsLockoutAfterTheRequestTransactionEnds() {
    exhaustAttempts();
    LocalDateTime lockedUntil = lockedUntil();
    assertThat(lockedUntil).isNotNull();

    // getStatus 는 자기 readOnly 트랜잭션에서 행을 새로 읽는다. 잠금이 요청 경계를 넘어 살아 있어야 한다.
    GuardianPinStatusResponse status = guardianPinService.getStatus(USER_ID);

    assertThat(status.pinConfigured()).isTrue();
    assertThat(status.locked()).isTrue();
    assertThat(status.remainingAttempts()).isZero();
    assertThat(status.retryAfterSeconds()).isBetween(1L, FIRST_LOCK_SECONDS);
    assertThat(status.lockedUntil()).isCloseTo(committedLockedUntil(), within(1, MILLIS));
  }

  @Test
  void doesNotCountFurtherFailuresWhileLocked() {
    exhaustAttempts();
    LocalDateTime lockedUntil = lockedUntil();

    GuardianPinStatusResponse status = verifyFails(GuardianPinErrorCode.PIN_LOCKED, WRONG_PIN);

    assertThat(status.locked()).isTrue();
    // 잠금 중 시도까지 세면 잠금 해제 시각이 계속 밀려 영구 잠금이 된다.
    assertThat(failedAttemptCount()).isZero();
    assertThat(lockoutLevel()).isEqualTo(1);
    assertThat(lockedUntil()).isEqualTo(lockedUntil);
  }

  @Test
  void countsFailureOnChangeWithoutCommittingTheNewHash() {
    String originalHash = pinHash();

    GuardianPinException thrown =
        (GuardianPinException)
            assertThatThrownBy(() -> guardianPinService.change(USER_ID, WRONG_PIN, NEW_PIN))
                .isInstanceOf(GuardianPinException.class)
                .actual();

    assertThat(thrown.getErrorCode()).isEqualTo(GuardianPinErrorCode.PIN_MISMATCH);
    assertThat(thrown.getStatus().remainingAttempts()).isEqualTo(UserGuardianPin.MAX_ATTEMPTS - 1);
    assertThat(failedAttemptCount()).isEqualTo(1);
    // noRollbackFor 가 성립하는 근거를 고정한다: 실패 카운터만 커밋되고 새 PIN 해시는 커밋되지 않는다.
    // 이 단언이 깨지면 현재 PIN 을 모르는 요청으로 PIN 이 교체된다는 뜻이다.
    assertThat(pinHash()).isEqualTo(originalHash);

    assertThat(guardianPinService.verify(USER_ID, PIN).locked()).isFalse();
  }

  @Test
  void commitsCounterResetOnSuccessfulVerification() {
    verifyFails(GuardianPinErrorCode.PIN_MISMATCH, WRONG_PIN);
    verifyFails(GuardianPinErrorCode.PIN_MISMATCH, WRONG_PIN);
    verifyFails(GuardianPinErrorCode.PIN_MISMATCH, WRONG_PIN);
    assertThat(failedAttemptCount()).isEqualTo(3);

    GuardianPinStatusResponse status = guardianPinService.verify(USER_ID, PIN);

    assertThat(status.locked()).isFalse();
    assertThat(status.remainingAttempts()).isEqualTo(UserGuardianPin.MAX_ATTEMPTS);
    assertThat(failedAttemptCount()).isZero();
    assertThat(lockoutLevel()).isZero();
    assertThat(lockedUntil()).isNull();
    assertThat(lastVerifiedAt()).isNotNull();
  }

  @Test
  void rejectsMalformedPinAsCommonValidationErrorBeforeReachingTheService() throws Exception {
    // PIN_INVALID 는 HTTP 경로로 도달하지 않는다. 요청 DTO 의 @Pattern 과 @Valid 가 먼저 걸러
    // COMMON_400_001 + ValidationErrorData 로 응답한다(Jira 879 오류 표의 "PIN_INVALID | 400 | data 없음"은
    // 사실과 다르다 — docs/api/guardian-pin-contract.md 참고).
    mockMvc
        .perform(
            post("/api/v1/users/me/guardian-pin/verifications")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"pin\":\"12a4\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.success").value(false))
        .andExpect(jsonPath("$.code").value("COMMON_400_001"))
        .andExpect(jsonPath("$.data.fieldErrors[0].field").value("pin"));

    // 서비스에 닿지 않으므로 실패 카운터도 늘지 않는다 — 형식 오류로 잠금이 다가오면 안 된다.
    assertThat(failedAttemptCount()).isZero();
  }

  /** 상한까지 실패시켜 잠금 상태를 만든다. 마지막 회차만 {@code PIN_LOCKED} 다. */
  private void exhaustAttempts() {
    for (int attempt = 1; attempt < UserGuardianPin.MAX_ATTEMPTS; attempt++) {
      verifyFails(GuardianPinErrorCode.PIN_MISMATCH, WRONG_PIN);
    }
    verifyFails(GuardianPinErrorCode.PIN_LOCKED, WRONG_PIN);
  }

  private GuardianPinStatusResponse verifyFails(
      GuardianPinErrorCode expected, String attemptedPin) {
    GuardianPinException thrown =
        (GuardianPinException)
            assertThatThrownBy(() -> guardianPinService.verify(USER_ID, attemptedPin))
                .isInstanceOf(GuardianPinException.class)
                .actual();
    assertThat(thrown.getErrorCode()).isEqualTo(expected);
    return thrown.getStatus();
  }

  private Integer failedAttemptCount() {
    return column("failed_attempt_count", Integer.class);
  }

  private Integer lockoutLevel() {
    return column("lockout_level", Integer.class);
  }

  private LocalDateTime lockedUntil() {
    return column("locked_until", LocalDateTime.class);
  }

  /**
   * 커밋된 잠금 해제 시각을 응답과 비교할 수 있는 {@link java.time.Instant} 로 읽는다.
   *
   * <p>정확히 같은 값을 기대할 수는 없다. {@code locked_until} 은 {@code DATETIME(6)} 이라 MySQL 이 나노초를 마이크로초로
   * <b>반올림</b>해 저장하는데, 응답에 실린 값은 서버 시계의 나노초 그대로다. 1ms 오차 안에서 같은지만 본다.
   */
  private java.time.Instant committedLockedUntil() {
    return lockedUntil().toInstant(ZoneOffset.UTC);
  }

  private LocalDateTime lastVerifiedAt() {
    return column("last_verified_at", LocalDateTime.class);
  }

  private String pinHash() {
    return column("pin_hash", String.class);
  }

  /** 트랜잭션 밖에서 행을 새로 읽는다. 영속 컨텍스트 캐시가 아니라 커밋된 값을 본다. */
  private <T> T column(String name, Class<T> type) {
    return jdbcTemplate.queryForObject(
        "select " + name + " from user_guardian_pins where user_id = ?", type, USER_ID);
  }

  private LocalDateTime utcNow() {
    return LocalDateTime.now(ZoneOffset.UTC);
  }

  private void setAuthenticatedUser(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
