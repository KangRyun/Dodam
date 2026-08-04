package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ErrorCode;
import com.ssafy.b209.user.domain.UserGuardianPin;
import com.ssafy.b209.user.dto.response.GuardianPinStatusResponse;
import com.ssafy.b209.user.exception.GuardianPinErrorCode;
import com.ssafy.b209.user.exception.GuardianPinException;
import com.ssafy.b209.user.repository.UserGuardianPinRepository;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 보호자 PIN 의 설정·검증·잠금·백오프·초기화 규칙을 고정한다 (S15P11B209-879).
 *
 * <p>시계를 고정하고 필요한 테스트에서만 앞으로 감아, 잠금 판정이 서버 시각에만 의존하는 것을 검증한다.
 */
@ExtendWith(MockitoExtension.class)
class GuardianPinServiceTest {

  private static final Long USER_ID = 41L;
  private static final Instant BASE = Instant.parse("2026-08-04T04:00:00Z");
  private static final String PIN = "1234";
  private static final String WRONG_PIN = "9999";

  @Mock private UserGuardianPinRepository pinRepository;
  @Mock private com.ssafy.b209.auth.repository.UserRepository userRepository;

  private MutableClock clock;
  private GuardianPinProperties properties;
  private GuardianPinHasher hasher;
  private GuardianPinService service;

  @BeforeEach
  void setUp() {
    clock = new MutableClock(BASE);
    properties = new GuardianPinProperties();
    properties.setPepper("test-pepper");
    // 테스트마다 BCrypt 를 12로 돌리면 느려진다. 강도는 보안 요구가 아니라 비용 설정이라 낮춰도 규칙 검증에 영향이 없다.
    properties.setHashStrength(4);
    hasher = new GuardianPinHasher(properties);
    service = new GuardianPinService(pinRepository, userRepository, hasher, properties, clock);
  }

  @Test
  void reportsPinNotConfiguredBeforeFirstSetup() {
    given(pinRepository.findById(USER_ID)).willReturn(Optional.empty());

    GuardianPinStatusResponse status = service.getStatus(USER_ID);

    assertThat(status.pinConfigured()).isFalse();
    assertThat(status.locked()).isFalse();
    assertThat(status.remainingAttempts()).isEqualTo(UserGuardianPin.MAX_ATTEMPTS);
    assertThat(status.serverTime()).isEqualTo(BASE);
  }

  @Test
  void configuresPinWithoutStoringRawValue() {
    given(pinRepository.existsById(USER_ID)).willReturn(false);
    given(pinRepository.save(any(UserGuardianPin.class)))
        .willAnswer(invocation -> invocation.getArgument(0));

    GuardianPinStatusResponse status = service.configure(USER_ID, PIN);

    assertThat(status.pinConfigured()).isTrue();
    // 해시만 저장한다. 원문·PIN 문자열이 그대로 담기지 않는다.
    UserGuardianPin saved = savedPin();
    assertThat(saved.getPinHash()).isNotEqualTo(PIN).doesNotContain(PIN);
    assertThat(saved.getHashAlgorithm()).isEqualTo(GuardianPinHasher.ALGORITHM);
  }

  @Test
  void rejectsSecondConfigureSoNobodyOverwritesUnknownPin() {
    given(pinRepository.existsById(USER_ID)).willReturn(true);

    assertError(() -> service.configure(USER_ID, PIN), GuardianPinErrorCode.PIN_ALREADY_CONFIGURED);
    verify(pinRepository, never()).save(any(UserGuardianPin.class));
  }

  @Test
  void rejectsNonFourDigitPin() {
    assertError(() -> service.configure(USER_ID, "12a4"), GuardianPinErrorCode.PIN_INVALID);
    assertError(() -> service.configure(USER_ID, "123"), GuardianPinErrorCode.PIN_INVALID);
    assertError(() -> service.configure(USER_ID, "12345"), GuardianPinErrorCode.PIN_INVALID);
    assertError(() -> service.configure(USER_ID, null), GuardianPinErrorCode.PIN_INVALID);
  }

  @Test
  void verifiesCorrectPinAndResetsAttempts() {
    UserGuardianPin pin = existingPin();
    pin.recordFailure(now());
    pin.recordFailure(now());
    givenLockedPin(pin);

    GuardianPinStatusResponse status = service.verify(USER_ID, PIN);

    assertThat(status.locked()).isFalse();
    assertThat(status.remainingAttempts()).isEqualTo(UserGuardianPin.MAX_ATTEMPTS);
    assertThat(pin.getFailedAttemptCount()).isZero();
    assertThat(pin.getLastVerifiedAt()).isEqualTo(now());
  }

  @Test
  void countsFailureAndTellsRemainingAttempts() {
    UserGuardianPin pin = existingPin();
    givenLockedPin(pin);

    GuardianPinStatusResponse status = assertPinFailure(GuardianPinErrorCode.PIN_MISMATCH);

    assertThat(status.remainingAttempts()).isEqualTo(4);
    assertThat(status.locked()).isFalse();
    assertThat(status.retryAfterSeconds()).isNull();
    assertThat(pin.getFailedAttemptCount()).isEqualTo(1);
  }

  @Test
  void locksAfterFiveFailuresWithRetryAfterSeconds() {
    UserGuardianPin pin = existingPin();
    givenLockedPin(pin);

    for (int attempt = 1; attempt <= UserGuardianPin.MAX_ATTEMPTS - 1; attempt++) {
      assertPinFailure(GuardianPinErrorCode.PIN_MISMATCH);
    }
    GuardianPinStatusResponse status = assertPinFailure(GuardianPinErrorCode.PIN_LOCKED);

    assertThat(status.locked()).isTrue();
    assertThat(status.remainingAttempts()).isZero();
    assertThat(status.retryAfterSeconds()).isEqualTo(30);
    assertThat(status.lockedUntil()).isEqualTo(BASE.plusSeconds(30));
  }

  @Test
  void rejectsVerificationWhileLockedWithoutCountingAnotherFailure() {
    UserGuardianPin pin = lockedPinAt(30);
    givenLockedPin(pin);

    GuardianPinStatusResponse status = assertPinFailure(GuardianPinErrorCode.PIN_LOCKED, PIN);

    assertThat(status.locked()).isTrue();
    assertThat(status.retryAfterSeconds()).isEqualTo(30);
    // 잠금 중에는 시도 자체를 받지 않으므로 실패 횟수가 더 늘지 않는다 — 잠금 시간을 계속 밀어내는 것을 막는다.
    assertThat(pin.getFailedAttemptCount()).isZero();
    verify(pinRepository, never()).saveAndFlush(any(UserGuardianPin.class));
  }

  @Test
  void raisesLockoutStepOnRepeatedLockouts() {
    // 고정 30초만 쓰면 분당 약 10회 시도가 가능해 4자리 조합을 하루 안에 훑는다. 단계가 올라가야 벽이 된다.
    UserGuardianPin pin = existingPin();
    givenLockedPin(pin);

    exhaustAttempts();
    assertThat(pin.getLockedUntil()).isEqualTo(now().plusSeconds(30));

    clock.advance(Duration.ofSeconds(31));
    exhaustAttempts();
    assertThat(pin.getLockedUntil()).isEqualTo(now().plusMinutes(1));

    clock.advance(Duration.ofMinutes(2));
    exhaustAttempts();
    assertThat(pin.getLockedUntil()).isEqualTo(now().plusMinutes(5));
  }

  @Test
  void unlocksOnceServerTimePassesLockedUntil() {
    UserGuardianPin pin = lockedPinAt(30);
    givenLockedPin(pin);
    given(pinRepository.saveAndFlush(any(UserGuardianPin.class)))
        .willAnswer(invocation -> invocation.getArgument(0));

    clock.advance(Duration.ofSeconds(31));
    GuardianPinStatusResponse status = service.verify(USER_ID, PIN);

    assertThat(status.locked()).isFalse();
    assertThat(status.retryAfterSeconds()).isNull();
  }

  @Test
  void successfulVerificationClearsLockoutLevelSoNextLockStartsAtThirtySeconds() {
    UserGuardianPin pin = existingPin();
    givenLockedPin(pin);
    exhaustAttempts();
    clock.advance(Duration.ofSeconds(31));

    service.verify(USER_ID, PIN);
    assertThat(pin.getLockoutLevel()).isZero();

    exhaustAttempts();
    assertThat(pin.getLockedUntil()).isEqualTo(now().plusSeconds(30));
  }

  @Test
  void changesPinOnlyAfterCurrentPinMatches() {
    UserGuardianPin pin = existingPin();
    String originalHash = pin.getPinHash();
    givenLockedPin(pin);
    given(pinRepository.saveAndFlush(any(UserGuardianPin.class)))
        .willAnswer(invocation -> invocation.getArgument(0));

    service.change(USER_ID, PIN, "5678");

    assertThat(pin.getPinHash()).isNotEqualTo(originalHash);
    assertThat(hasher.matches("5678", pin.getPinHash())).isTrue();
  }

  @Test
  void countsFailureWhenChangeUsesWrongCurrentPin() {
    // 변경 경로를 무한 시도 창구로 열어 두면 검증 잠금이 우회된다.
    UserGuardianPin pin = existingPin();
    givenLockedPin(pin);
    given(pinRepository.saveAndFlush(any(UserGuardianPin.class)))
        .willAnswer(invocation -> invocation.getArgument(0));

    assertThatThrownBy(() -> service.change(USER_ID, WRONG_PIN, "5678"))
        .isInstanceOf(GuardianPinException.class);

    assertThat(pin.getFailedAttemptCount()).isEqualTo(1);
  }

  @Test
  void reportsPinNotConfiguredWhenVerifyingWithoutPin() {
    given(pinRepository.findByUserIdForUpdate(USER_ID)).willReturn(Optional.empty());

    assertError(() -> service.verify(USER_ID, PIN), GuardianPinErrorCode.PIN_NOT_CONFIGURED);
  }

  @Test
  void resetsPinOnlyRightAfterSocialReauthentication() {
    User user = userLoggedInAt(now().minusMinutes(1));
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(user));

    GuardianPinStatusResponse status = service.reset(USER_ID);

    assertThat(status.pinConfigured()).isFalse();
    verify(pinRepository).deleteById(USER_ID);
  }

  @Test
  void refusesResetOutsideReauthenticationWindow() {
    // 단순 로그아웃만으로 풀리면 아이가 로그아웃을 눌러 잠금을 없앨 수 있다.
    User user = userLoggedInAt(now().minusMinutes(10));
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(user));

    assertError(() -> service.reset(USER_ID), GuardianPinErrorCode.PIN_RESET_REQUIRED);
    verify(pinRepository, never()).deleteById(USER_ID);
  }

  @Test
  void refusesResetWhenLastLoginIsUnknown() {
    User user = userLoggedInAt(null);
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(user));

    assertError(() -> service.reset(USER_ID), GuardianPinErrorCode.PIN_RESET_REQUIRED);
  }

  @Test
  void rejectsEveryOperationWhenPepperIsMissing() {
    // 부팅은 되고 PIN API 만 막힌다. PIN 과 무관한 기능까지 멈추면 손실이 더 크다.
    properties.setPepper("");
    GuardianPinService unavailable =
        new GuardianPinService(
            pinRepository, userRepository, new GuardianPinHasher(properties), properties, clock);

    assertError(() -> unavailable.getStatus(USER_ID), GuardianPinErrorCode.PIN_UNAVAILABLE);
    assertError(() -> unavailable.configure(USER_ID, PIN), GuardianPinErrorCode.PIN_UNAVAILABLE);
    assertError(() -> unavailable.verify(USER_ID, PIN), GuardianPinErrorCode.PIN_UNAVAILABLE);
    assertError(() -> unavailable.reset(USER_ID), GuardianPinErrorCode.PIN_UNAVAILABLE);
  }

  private void exhaustAttempts() {
    for (int attempt = 1; attempt <= UserGuardianPin.MAX_ATTEMPTS; attempt++) {
      assertThatThrownBy(() -> service.verify(USER_ID, WRONG_PIN))
          .isInstanceOf(GuardianPinException.class);
    }
  }

  private GuardianPinStatusResponse assertPinFailure(GuardianPinErrorCode expected) {
    return assertPinFailure(expected, WRONG_PIN);
  }

  private GuardianPinStatusResponse assertPinFailure(
      GuardianPinErrorCode expected, String attemptedPin) {
    GuardianPinException thrown =
        (GuardianPinException)
            assertThatThrownBy(() -> service.verify(USER_ID, attemptedPin))
                .isInstanceOf(GuardianPinException.class)
                .actual();
    assertThat(thrown.getErrorCode()).isEqualTo(expected);
    return thrown.getStatus();
  }

  private void givenLockedPin(UserGuardianPin pin) {
    given(pinRepository.findByUserIdForUpdate(USER_ID)).willReturn(Optional.of(pin));
    lenient()
        .when(pinRepository.saveAndFlush(any(UserGuardianPin.class)))
        .thenAnswer(invocation -> invocation.getArgument(0));
  }

  private UserGuardianPin existingPin() {
    return UserGuardianPin.create(USER_ID, hasher.hash(PIN), GuardianPinHasher.ALGORITHM, now());
  }

  private UserGuardianPin lockedPinAt(int lockSeconds) {
    UserGuardianPin pin = existingPin();
    for (int attempt = 1; attempt <= UserGuardianPin.MAX_ATTEMPTS; attempt++) {
      pin.recordFailure(now());
    }
    assertThat(pin.getLockedUntil()).isEqualTo(now().plusSeconds(lockSeconds));
    return pin;
  }

  private User userLoggedInAt(LocalDateTime lastLoginAt) {
    User user = org.mockito.Mockito.mock(User.class);
    lenient().when(user.getLastLoginAt()).thenReturn(lastLoginAt);
    return user;
  }

  private UserGuardianPin savedPin() {
    org.mockito.ArgumentCaptor<UserGuardianPin> captor =
        org.mockito.ArgumentCaptor.forClass(UserGuardianPin.class);
    verify(pinRepository).save(captor.capture());
    return captor.getValue();
  }

  private LocalDateTime now() {
    return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
  }

  private void assertError(Runnable invocation, ErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }

  /** 잠금 경과를 재현하려면 시계를 앞으로 감아야 한다. {@code Clock.fixed} 로는 시간이 흐르지 않는다. */
  private static final class MutableClock extends Clock {
    private Instant instant;

    private MutableClock(Instant instant) {
      this.instant = instant;
    }

    private void advance(Duration amount) {
      instant = instant.plus(amount);
    }

    @Override
    public java.time.ZoneId getZone() {
      return ZoneOffset.UTC;
    }

    @Override
    public Clock withZone(java.time.ZoneId zone) {
      return this;
    }

    @Override
    public Instant instant() {
      return instant;
    }
  }
}
