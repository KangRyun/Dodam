package com.ssafy.b209.user.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.domain.UserGuardianPin;
import com.ssafy.b209.user.dto.response.GuardianPinStatusResponse;
import com.ssafy.b209.user.exception.GuardianPinErrorCode;
import com.ssafy.b209.user.exception.GuardianPinException;
import com.ssafy.b209.user.exception.UserErrorCode;
import com.ssafy.b209.user.repository.UserGuardianPinRepository;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자 PIN 설정·변경·검증·초기화 Use Case다 (S15P11B209-879).
 *
 * <p>아동 모드에서 보호자 홈으로 돌아올 때 요구하는 잠금이며, 보호자 계정당 하나다.
 *
 * <p><b>이 서비스가 하지 않는 것.</b> 검증 성공 상태를 서버가 들고 있지 않는다. "지금 이 앱이 보호자 모드로 열려 있다"는 상태는 앱 메모리에서만 관리하고, 아동
 * 모드 재진입·로그아웃·백그라운드 복귀 시 재잠금도 클라이언트 책임이다. 짧은 수명의 해제 증표도 발급하지 않는다 — 보호자 API 권한은 이미 Access Token 으로
 * 통제되므로 증표가 있어도 "PIN 없이 Token 으로 직접 호출"은 막지 못하고, 저장·만료·검증 경로만 늘어난다.
 *
 * <p>또한 "첫 아동 모드 진입 전에 PIN 을 설정하게 한다"는 정책도 서버가 강제할 수 없다. 아동 모드 진입은 서버 API 가 아니라 앱 내 화면 전환이다. 서버는
 * {@code pinConfigured} 를 알려주고, 게이트는 클라이언트가 세운다.
 *
 * <p>모든 시각 판단은 주입된 {@link Clock}(UTC) 으로만 한다. 기기 시계는 신뢰하지 않는다.
 */
@Service
public class GuardianPinService {

  private static final Logger log = LoggerFactory.getLogger(GuardianPinService.class);

  /** 숫자 4자리. 형식 위반은 해시 비교 전에 거른다. */
  private static final Pattern PIN_PATTERN = Pattern.compile("^\\d{4}$");

  private final UserGuardianPinRepository pinRepository;
  private final UserRepository userRepository;
  private final GuardianPinHasher hasher;
  private final GuardianPinProperties properties;
  private final Clock clock;

  /**
   * PIN 저장소와 해시·설정·시계를 주입받는다.
   *
   * @param pinRepository 보호자 PIN 저장소
   * @param userRepository 초기화 시 소셜 재인증 시각을 확인할 사용자 저장소
   * @param hasher pepper 적용 해시 경계
   * @param properties 초기화 재인증 창 등 정책 설정
   * @param clock 서버 기준 UTC 시계
   */
  public GuardianPinService(
      UserGuardianPinRepository pinRepository,
      UserRepository userRepository,
      GuardianPinHasher hasher,
      GuardianPinProperties properties,
      Clock clock) {
    this.pinRepository = pinRepository;
    this.userRepository = userRepository;
    this.hasher = hasher;
    this.properties = properties;
    this.clock = clock;
  }

  /**
   * PIN 설정 여부와 잠금 상태를 조회한다.
   *
   * @param userId 인증된 보호자 사용자 ID
   * @return 현재 상태이며 PIN 이 없으면 {@code pinConfigured=false}
   */
  @Transactional(readOnly = true)
  public GuardianPinStatusResponse getStatus(Long userId) {
    requireAvailable();
    LocalDateTime now = now();
    return pinRepository.findById(userId).map(pin -> status(pin, now)).orElseGet(() -> absent(now));
  }

  /**
   * PIN 을 최초로 설정한다.
   *
   * <p>이미 있으면 덮어쓰지 않는다. 덮어쓰기를 허용하면 현재 PIN 을 모르는 사람이 새 PIN 으로 갈아 끼울 수 있어 잠금이 무의미해진다 — 변경은 현재 PIN 을
   * 확인하는 경로로만 한다.
   *
   * @param userId 인증된 보호자 사용자 ID
   * @param rawPin 숫자 4자리 PIN
   * @return 설정 후 상태
   * @throws BusinessException 형식 위반, 이미 설정됨, pepper 미구성
   */
  @Transactional
  public GuardianPinStatusResponse configure(Long userId, String rawPin) {
    requireAvailable();
    requireFormat(rawPin);
    if (pinRepository.existsById(userId)) {
      throw new BusinessException(GuardianPinErrorCode.PIN_ALREADY_CONFIGURED);
    }
    LocalDateTime now = now();
    UserGuardianPin saved =
        pinRepository.save(
            UserGuardianPin.create(userId, hasher.hash(rawPin), hasher.algorithm(), now));
    log.info("보호자 PIN을 설정했습니다. userId={}", userId);
    return status(saved, now);
  }

  /**
   * 현재 PIN 을 확인하고 새 PIN 으로 바꾼다.
   *
   * <p>현재 PIN 확인은 검증과 같은 규칙을 따른다 — 틀리면 실패로 세고 상한에 닿으면 잠근다. 변경 경로를 무한 시도 창구로 열어 두면 검증 잠금이 우회된다.
   *
   * @param userId 인증된 보호자 사용자 ID
   * @param currentPin 현재 PIN
   * @param newPin 새 PIN
   * @return 변경 후 상태
   */
  @Transactional
  public GuardianPinStatusResponse change(Long userId, String currentPin, String newPin) {
    requireAvailable();
    requireFormat(currentPin);
    requireFormat(newPin);

    LocalDateTime now = now();
    UserGuardianPin pin = lockedPin(userId, now);
    if (!hasher.matches(currentPin, pin.getPinHash())) {
      return failVerification(pin, now);
    }
    pin.changeTo(hasher.hash(newPin), hasher.algorithm());
    pinRepository.saveAndFlush(pin);
    log.info("보호자 PIN을 변경했습니다. userId={}", userId);
    return status(pin, now);
  }

  /**
   * PIN 을 검증한다.
   *
   * @param userId 인증된 보호자 사용자 ID
   * @param rawPin 입력 PIN
   * @return 검증 성공 시 초기화된 상태
   * @throws GuardianPinException 불일치·잠금. 응답 {@code data} 에 남은 시도·해제 시각을 함께 싣는다
   */
  @Transactional
  public GuardianPinStatusResponse verify(Long userId, String rawPin) {
    requireAvailable();
    requireFormat(rawPin);

    LocalDateTime now = now();
    UserGuardianPin pin = lockedPin(userId, now);
    if (!hasher.matches(rawPin, pin.getPinHash())) {
      return failVerification(pin, now);
    }
    pin.recordSuccess(now);
    pinRepository.saveAndFlush(pin);
    return status(pin, now);
  }

  /**
   * PIN 을 초기화한다. 분실 시 다시 설정하기 위한 경로다.
   *
   * <p><b>소셜 재인증이 필수다.</b> 단순 로그아웃만으로 풀리면 아이가 로그아웃 버튼을 눌러 잠금을 없앨 수 있다. 새 토큰 타입을 만들지 않고 {@code
   * users.last_login_at} 이 재인증 창 안인지로 판정한다 — 방금 소셜 로그인을 통과했다는 사실을 재사용한다.
   *
   * @param userId 인증된 보호자 사용자 ID
   * @return 초기화 후 상태({@code pinConfigured=false})
   * @throws BusinessException 재인증 창을 벗어난 경우 {@code PIN_RESET_REQUIRED}
   */
  @Transactional
  public GuardianPinStatusResponse reset(Long userId) {
    requireAvailable();
    User user =
        userRepository
            .findById(userId)
            .orElseThrow(() -> new BusinessException(UserErrorCode.USER_NOT_FOUND));
    LocalDateTime now = now();
    if (!isRecentlyReauthenticated(user, now)) {
      throw new BusinessException(GuardianPinErrorCode.PIN_RESET_REQUIRED);
    }
    pinRepository.deleteById(userId);
    log.info("보호자 PIN을 초기화했습니다. userId={}", userId);
    return absent(now);
  }

  /**
   * 마지막 로그인이 재인증 창 안인지 본다.
   *
   * <p>{@code last_login_at} 이 비어 있으면(과거 데이터·비정상) 초기화를 허용하지 않는다. 판단 근거가 없을 때 잠금을 푸는 쪽으로 기울면 안 된다.
   */
  private boolean isRecentlyReauthenticated(User user, LocalDateTime now) {
    LocalDateTime lastLoginAt = user.getLastLoginAt();
    if (lastLoginAt == null) {
      return false;
    }
    Duration window = Duration.ofMinutes(properties.getResetReauthWindowMinutes());
    return !lastLoginAt.isBefore(now.minus(window));
  }

  /**
   * 검증·변경 경로에서 잠금을 획득해 PIN 을 읽고, 잠금 중이면 즉시 거부한다.
   *
   * <p>행 단위 배타 락으로 동시 요청을 직렬화한다. 락이 없으면 두 요청이 같은 실패 횟수를 읽어 각자 +1 해서 저장하고, 실패 하나가 사라져 시도 횟수를 늘려 준다.
   */
  private UserGuardianPin lockedPin(Long userId, LocalDateTime now) {
    UserGuardianPin pin =
        pinRepository
            .findByUserIdForUpdate(userId)
            .orElseThrow(() -> new BusinessException(GuardianPinErrorCode.PIN_NOT_CONFIGURED));
    if (pin.isLocked(now)) {
      throw new GuardianPinException(GuardianPinErrorCode.PIN_LOCKED, status(pin, now));
    }
    return pin;
  }

  /** 실패를 기록하고 현재 상태와 함께 거부한다. 잠기면 코드가 {@code PIN_LOCKED} 로 바뀐다. */
  private GuardianPinStatusResponse failVerification(UserGuardianPin pin, LocalDateTime now) {
    pin.recordFailure(now);
    pinRepository.saveAndFlush(pin);
    GuardianPinStatusResponse status = status(pin, now);
    // PIN 원문은 남기지 않는다. 잠금 판단에 필요한 수치만 남긴다.
    log.info(
        "보호자 PIN 검증에 실패했습니다. userId={}, remainingAttempts={}, lockoutLevel={}, locked={}",
        pin.getUserId(),
        status.remainingAttempts(),
        pin.getLockoutLevel(),
        status.locked());
    GuardianPinErrorCode errorCode =
        status.locked() ? GuardianPinErrorCode.PIN_LOCKED : GuardianPinErrorCode.PIN_MISMATCH;
    throw new GuardianPinException(errorCode, status);
  }

  private void requireAvailable() {
    if (!hasher.isConfigured()) {
      throw new BusinessException(GuardianPinErrorCode.PIN_UNAVAILABLE);
    }
  }

  private void requireFormat(String rawPin) {
    if (rawPin == null || !PIN_PATTERN.matcher(rawPin).matches()) {
      throw new BusinessException(GuardianPinErrorCode.PIN_INVALID);
    }
  }

  private GuardianPinStatusResponse status(UserGuardianPin pin, LocalDateTime now) {
    boolean locked = pin.isLocked(now);
    return new GuardianPinStatusResponse(
        true,
        locked,
        pin.remainingAttempts(now),
        pin.retryAfterSeconds(now),
        locked ? toInstant(pin.getLockedUntil()) : null,
        toInstant(now));
  }

  /** PIN 이 없을 때의 상태다. 잠금 개념이 없으므로 시도 횟수는 상한 그대로 준다. */
  private GuardianPinStatusResponse absent(LocalDateTime now) {
    return new GuardianPinStatusResponse(
        false, false, UserGuardianPin.MAX_ATTEMPTS, null, null, toInstant(now));
  }

  private LocalDateTime now() {
    return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
  }

  private java.time.Instant toInstant(LocalDateTime value) {
    return value == null ? null : value.toInstant(ZoneOffset.UTC);
  }
}
