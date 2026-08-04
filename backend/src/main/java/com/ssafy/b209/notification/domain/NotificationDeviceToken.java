package com.ssafy.b209.notification.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/**
 * 보호자 기기에 발급된 Push Token이다.
 *
 * <p>Token 원문은 보관하지 않는다. 발송에 필요한 값은 {@code tokenCiphertext}로 봉인해 저장하고, 동일 Token 판별은 {@code
 * tokenHash}로만 수행한다. 같은 기기의 갱신은 {@code (userId, deviceId)} 조합으로 찾는다.
 */
@Entity
@Table(name = "notification_device_tokens")
public class NotificationDeviceToken {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "user_id", nullable = false)
  private Long userId;

  @Column(name = "device_id", nullable = false, length = 100)
  private String deviceId;

  @Column(name = "token_ciphertext", nullable = false, length = 1500)
  private String tokenCiphertext;

  // DB는 CHAR(64)다. length만 지정하면 VARCHAR로 검증돼 ddl-auto=validate가 거부한다.
  @Column(name = "token_hash", nullable = false, columnDefinition = "CHAR(64)")
  private String tokenHash;

  @Column(name = "platform", nullable = false, length = 20)
  private String platform;

  @Column(name = "push_provider", nullable = false, length = 20)
  private String pushProvider;

  @Column(name = "app_version", length = 20)
  private String appVersion;

  @Column(name = "is_active", nullable = false)
  private boolean active;

  @Column(name = "last_used_at")
  private LocalDateTime lastUsedAt;

  @Column(name = "created_at", nullable = false, updatable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
  private LocalDateTime updatedAt;

  protected NotificationDeviceToken() {}

  private NotificationDeviceToken(
      Long userId,
      String deviceId,
      String tokenCiphertext,
      String tokenHash,
      String platform,
      String pushProvider,
      String appVersion,
      LocalDateTime now) {
    this.userId = userId;
    this.deviceId = deviceId;
    this.tokenCiphertext = tokenCiphertext;
    this.tokenHash = tokenHash;
    this.platform = platform;
    this.pushProvider = pushProvider;
    this.appVersion = appVersion;
    this.active = true;
    this.createdAt = now;
  }

  /**
   * 새 기기 Token을 활성 상태로 만든다.
   *
   * @param userId 소유 사용자 ID
   * @param deviceId 클라이언트 설치 식별자
   * @param tokenCiphertext 봉인된 Token
   * @param tokenHash Token SHA-256 hash
   * @param platform {@code ANDROID}, {@code IOS}, {@code WEB}
   * @param pushProvider {@code FCM} 또는 {@code APNS}
   * @param appVersion 등록 시점 앱 버전이며 없으면 {@code null}
   * @param now 서버 기준 생성 시각
   * @return 활성 상태의 새 기기 Token
   */
  public static NotificationDeviceToken register(
      Long userId,
      String deviceId,
      String tokenCiphertext,
      String tokenHash,
      String platform,
      String pushProvider,
      String appVersion,
      LocalDateTime now) {
    return new NotificationDeviceToken(
        userId, deviceId, tokenCiphertext, tokenHash, platform, pushProvider, appVersion, now);
  }

  /**
   * 같은 기기가 새 Token을 보고했을 때 저장 값을 교체하고 다시 활성화한다.
   *
   * <p>비활성 상태였던 기기가 재등록하면 활성으로 돌아온다. 해제 후 재로그인이 정상 경로이기 때문이다.
   *
   * @param tokenCiphertext 새로 봉인한 Token
   * @param tokenHash 새 Token의 SHA-256 hash
   * @param platform 보고된 Platform
   * @param pushProvider 보고된 Push Provider
   * @param appVersion 보고된 앱 버전이며 없으면 {@code null}
   */
  public void refresh(
      String tokenCiphertext,
      String tokenHash,
      String platform,
      String pushProvider,
      String appVersion) {
    this.tokenCiphertext = tokenCiphertext;
    this.tokenHash = tokenHash;
    this.platform = platform;
    this.pushProvider = pushProvider;
    this.appVersion = appVersion;
    this.active = true;
  }

  /**
   * 이 Token 행의 소유자와 설치 식별자를 바꾼다.
   *
   * <p>{@code token_hash}에 전역 유니크 제약이 걸려 있어(V3 {@code uk_notification_device_tokens_hash}) 같은
   * Token으로 행을 하나 더 만들 수 없다. 그래서 같은 기기가 다른 계정으로 다시 등록할 때는 행을 새로 만들지 않고 이 행을 옮겨 쓴다.
   *
   * <p>호출 전에 <b>이전 소유자의 등록이 해제된 상태인지</b> 반드시 확인해야 한다. 활성 상태에서 옮기면 이전 사용자에게 갈 알림이 새 사용자 기기로 배달된다 —
   * 계약(`notification-inbox-contract.md` §3)이 소유권 자동 이전을 금지한 이유가 그것이다.
   *
   * @param userId 새 소유 사용자 ID
   * @param deviceId 새 설치 식별자
   */
  public void transferTo(Long userId, String deviceId) {
    this.userId = userId;
    this.deviceId = deviceId;
  }

  /** 기기 Token을 비활성화한다. 발송 대상에서 제외되며 행은 남긴다. */
  public void deactivate() {
    this.active = false;
  }

  public Long getId() {
    return id;
  }

  public Long getUserId() {
    return userId;
  }

  public String getDeviceId() {
    return deviceId;
  }

  public String getTokenCiphertext() {
    return tokenCiphertext;
  }

  public String getTokenHash() {
    return tokenHash;
  }

  public String getPlatform() {
    return platform;
  }

  public String getPushProvider() {
    return pushProvider;
  }

  public String getAppVersion() {
    return appVersion;
  }

  public boolean isActive() {
    return active;
  }

  public LocalDateTime getLastUsedAt() {
    return lastUsedAt;
  }

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  public LocalDateTime getUpdatedAt() {
    return updatedAt;
  }
}
