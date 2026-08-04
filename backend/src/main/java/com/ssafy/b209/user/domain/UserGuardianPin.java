package com.ssafy.b209.user.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;

/**
 * 보호자 계정 하나에 대응하는 PIN 이다 (S15P11B209-879).
 *
 * <p>아동 모드에서 보호자 홈으로 돌아올 때 요구하는 4자리 잠금이다. {@code userId} 가 PK 라 계정당 하나만 존재하며 아이별 PIN 은 없다.
 *
 * <p>PIN 원문은 보관하지 않는다. pepper 를 거친 값의 해시만 저장하고, 비교도 해시로만 한다.
 *
 * <p><b>잠금은 지수 백오프다.</b> 실패가 {@link #MAX_ATTEMPTS}에 닿으면 잠기고, 잠금이 풀린 뒤 또 그만큼 실패하면 다음 단계로 올라가 잠금 시간이
 * 길어진다. 고정 30초만 쓰면 분당 약 10회 시도가 가능해 4자리 조합 10,000개를 하루 안에 훑을 수 있다. 검증에 성공하면 실패 횟수와 단계를 함께 0으로 되돌린다
 * — 정상 사용자는 백오프를 체감하지 않는다.
 */
@Entity
@Table(name = "user_guardian_pins")
public class UserGuardianPin {

  /** 이 횟수만큼 연속 실패하면 잠근다. */
  public static final int MAX_ATTEMPTS = 5;

  /**
   * 백오프 단계별 잠금 시간이다. 마지막 값이 상한이며 그 뒤로는 더 길어지지 않는다.
   *
   * <p>상한을 1시간으로 둔 이유는 균형이다. 더 길게 잠그면 PIN 을 잊은 보호자가 아이를 달래는 동안 아무것도 못 하게 되고(초기화 경로는 소셜 재인증이 필요해 즉시
   * 풀리지 않는다), 더 짧게 두면 공격자에게 의미 있는 벽이 되지 않는다.
   */
  private static final List<Duration> LOCKOUT_STEPS =
      List.of(
          Duration.ofSeconds(30),
          Duration.ofMinutes(1),
          Duration.ofMinutes(5),
          Duration.ofMinutes(15),
          Duration.ofHours(1));

  @Id
  @Column(name = "user_id", nullable = false, updatable = false)
  private Long userId;

  @Column(name = "pin_hash", nullable = false, length = 255)
  private String pinHash;

  @Column(name = "hash_algorithm", nullable = false, length = 30)
  private String hashAlgorithm;

  @Column(name = "failed_attempt_count", nullable = false)
  private int failedAttemptCount;

  @Column(name = "lockout_level", nullable = false)
  private int lockoutLevel;

  @Column(name = "locked_until")
  private LocalDateTime lockedUntil;

  @Column(name = "last_verified_at")
  private LocalDateTime lastVerifiedAt;

  @Column(name = "created_at", nullable = false, updatable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
  private LocalDateTime updatedAt;

  protected UserGuardianPin() {}

  private UserGuardianPin(Long userId, String pinHash, String hashAlgorithm, LocalDateTime now) {
    this.userId = userId;
    this.pinHash = pinHash;
    this.hashAlgorithm = hashAlgorithm;
    this.failedAttemptCount = 0;
    this.lockoutLevel = 0;
    this.createdAt = now;
  }

  /**
   * 새 PIN 을 만든다.
   *
   * @param userId 보호자 사용자 ID
   * @param pinHash pepper 를 거친 값의 해시
   * @param hashAlgorithm 해시 알고리즘 식별자
   * @param now 서버 기준 생성 시각(UTC)
   * @return 잠금·실패 이력이 없는 새 PIN
   */
  public static UserGuardianPin create(
      Long userId, String pinHash, String hashAlgorithm, LocalDateTime now) {
    return new UserGuardianPin(userId, pinHash, hashAlgorithm, now);
  }

  /**
   * PIN 을 새 값으로 바꾸고 잠금·실패 이력을 초기화한다.
   *
   * <p>변경은 현재 PIN 을 확인한 뒤에만 도달하므로 실패 이력을 남길 이유가 없다.
   *
   * @param pinHash 새 해시
   * @param hashAlgorithm 해시 알고리즘 식별자
   */
  public void changeTo(String pinHash, String hashAlgorithm) {
    this.pinHash = pinHash;
    this.hashAlgorithm = hashAlgorithm;
    resetAttempts();
  }

  /**
   * 지금 잠겨 있는지 판단한다.
   *
   * <p>기기 시계가 아니라 서버 시각으로만 판단한다.
   *
   * @param now 서버 기준 현재 시각(UTC)
   * @return 잠금 해제 시각이 아직 지나지 않았으면 {@code true}
   */
  public boolean isLocked(LocalDateTime now) {
    return lockedUntil != null && lockedUntil.isAfter(now);
  }

  /**
   * 잠금 해제까지 남은 시간을 초로 반환한다.
   *
   * <p>1초 미만이 남아도 0을 주지 않고 1을 준다. 0은 클라이언트에서 "이제 시도 가능"으로 읽히는데 서버는 아직 거부한다.
   *
   * @param now 서버 기준 현재 시각(UTC)
   * @return 남은 초이며 잠금 중이 아니면 {@code null}
   */
  public Long retryAfterSeconds(LocalDateTime now) {
    if (!isLocked(now)) {
      return null;
    }
    long seconds = Duration.between(now, lockedUntil).toSeconds();
    return seconds <= 0 ? 1L : seconds;
  }

  /**
   * 남은 시도 횟수를 반환한다. 잠금 중이면 0이다.
   *
   * @param now 서버 기준 현재 시각(UTC)
   * @return 잠기기 전까지 남은 시도 횟수
   */
  public int remainingAttempts(LocalDateTime now) {
    if (isLocked(now)) {
      return 0;
    }
    int remaining = MAX_ATTEMPTS - failedAttemptCount;
    return Math.max(remaining, 0);
  }

  /** 검증 성공을 반영한다. 실패 횟수와 백오프 단계를 함께 0으로 되돌린다. */
  public void recordSuccess(LocalDateTime now) {
    resetAttempts();
    this.lastVerifiedAt = now;
  }

  /**
   * 검증 실패를 반영하고, 상한에 닿으면 잠근다.
   *
   * <p>잠글 때 백오프 단계를 한 칸 올린다. 실패 횟수는 0으로 되돌려 잠금이 풀린 뒤 다시 {@link #MAX_ATTEMPTS}번의 기회를 준다 — 그 기회를 또
   * 소진하면 한 단계 더 긴 잠금이 걸린다.
   *
   * @param now 서버 기준 현재 시각(UTC)
   */
  public void recordFailure(LocalDateTime now) {
    this.failedAttemptCount += 1;
    if (this.failedAttemptCount < MAX_ATTEMPTS) {
      return;
    }
    Duration lockDuration = LOCKOUT_STEPS.get(Math.min(lockoutLevel, LOCKOUT_STEPS.size() - 1));
    this.lockedUntil = now.plus(lockDuration);
    this.lockoutLevel = Math.min(lockoutLevel + 1, LOCKOUT_STEPS.size());
    this.failedAttemptCount = 0;
  }

  private void resetAttempts() {
    this.failedAttemptCount = 0;
    this.lockoutLevel = 0;
    this.lockedUntil = null;
  }

  public Long getUserId() {
    return userId;
  }

  public String getPinHash() {
    return pinHash;
  }

  public String getHashAlgorithm() {
    return hashAlgorithm;
  }

  public int getFailedAttemptCount() {
    return failedAttemptCount;
  }

  public int getLockoutLevel() {
    return lockoutLevel;
  }

  public LocalDateTime getLockedUntil() {
    return lockedUntil;
  }

  public LocalDateTime getLastVerifiedAt() {
    return lastVerifiedAt;
  }

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  public LocalDateTime getUpdatedAt() {
    return updatedAt;
  }
}
