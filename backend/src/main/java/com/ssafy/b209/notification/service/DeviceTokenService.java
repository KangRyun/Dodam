package com.ssafy.b209.notification.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.domain.NotificationDeviceToken;
import com.ssafy.b209.notification.dto.request.RegisterDeviceTokenRequest;
import com.ssafy.b209.notification.dto.response.DeviceTokenResponse;
import com.ssafy.b209.notification.exception.NotificationErrorCode;
import com.ssafy.b209.notification.repository.NotificationDeviceTokenRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.HexFormat;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * NOTI-01·NOTI-02 기기 Token 등록·갱신·해제 Use Case다.
 *
 * <p>같은 설치 식별자는 갱신으로 처리해 행을 늘리지 않는다. Token 원문은 봉인해 저장하고 동일성 비교는 SHA-256 hash로만 한다. 해제는 행을 지우지 않고
 * 비활성화한다. 발송 이력·감사를 위해 기기 기록 자체는 남긴다.
 */
@Service
public class DeviceTokenService {

  private static final Logger log = LoggerFactory.getLogger(DeviceTokenService.class);

  private static final Set<String> ALLOWED_PLATFORMS = Set.of("ANDROID", "IOS", "WEB");
  private static final int MAX_DEVICE_ID_LENGTH = 100;
  private static final int MAX_APP_VERSION_LENGTH = 20;
  private static final int HASH_PREFIX_LENGTH = 8;

  /**
   * 현재는 iOS도 Firebase가 발급한 등록 Token을 사용하므로 Provider를 FCM으로 고정한다. APNs 직접 연동을 도입하면 Platform에 따라
   * 분기한다.
   */
  private static final String PUSH_PROVIDER = "FCM";

  private final NotificationDeviceTokenRepository deviceTokenRepository;
  private final DeviceTokenCipher cipher;
  private final Clock clock;

  /**
   * 저장소, 봉인 도구, 시각 기준을 연결한다.
   *
   * @param deviceTokenRepository 설치 식별자 기반 upsert 저장소
   * @param cipher Token 봉인·복원 경계
   * @param clock 서버 기준 시계
   */
  public DeviceTokenService(
      NotificationDeviceTokenRepository deviceTokenRepository,
      DeviceTokenCipher cipher,
      Clock clock) {
    this.deviceTokenRepository = deviceTokenRepository;
    this.cipher = cipher;
    this.clock = clock;
  }

  /**
   * 기기 Token을 등록하거나 같은 설치 식별자의 기존 Token을 갱신한다.
   *
   * @param userId 인증된 사용자 ID
   * @param request 설치 식별자·Platform·Token·앱 버전
   * @return 저장 결과이며 Token 값은 포함하지 않는다
   * @throws BusinessException 요청 값이 계약을 만족하지 않거나, 암호화 키가 없거나, 다른 계정에 등록된 Token인 경우
   */
  @Transactional
  public DeviceTokenResponse register(Long userId, RegisterDeviceTokenRequest request) {
    String deviceId = requireDeviceId(request);
    String platform = requirePlatform(request);
    String pushToken = requirePushToken(request);
    String appVersion = normalizeAppVersion(request.appVersion());

    String tokenHash = hash(pushToken);
    NotificationDeviceToken tokenOwner =
        deviceTokenRepository.findByTokenHash(tokenHash).orElse(null);
    rejectTokenActiveOnAnotherUser(userId, tokenOwner);
    String ciphertext = cipher.encrypt(pushToken);

    if (tokenOwner != null && !isSameRegistration(tokenOwner, userId, deviceId)) {
      return response(
          claimToken(tokenOwner, userId, deviceId, ciphertext, tokenHash, platform, appVersion),
          true);
    }

    NotificationDeviceToken saved =
        deviceTokenRepository
            .findByUserIdAndDeviceId(userId, deviceId)
            .map(
                existing -> {
                  existing.refresh(ciphertext, tokenHash, platform, PUSH_PROVIDER, appVersion);
                  return deviceTokenRepository.saveAndFlush(existing);
                })
            .orElse(null);
    if (saved != null) {
      return response(saved, false);
    }

    NotificationDeviceToken created =
        deviceTokenRepository.saveAndFlush(
            NotificationDeviceToken.register(
                userId,
                deviceId,
                ciphertext,
                tokenHash,
                platform,
                PUSH_PROVIDER,
                appVersion,
                LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)));
    return response(created, true);
  }

  /**
   * 설치 식별자로 기기 Token을 비활성화한다.
   *
   * <p>이미 비활성인 기기도 성공으로 처리한다. 로그아웃 재시도가 오류로 보이지 않아야 한다.
   *
   * @param userId 인증된 사용자 ID
   * @param deviceId 해제할 설치 식별자
   * @throws BusinessException 해당 사용자에게 등록된 기기가 없는 경우
   */
  @Transactional
  public void release(Long userId, String deviceId) {
    NotificationDeviceToken deviceToken =
        deviceTokenRepository
            .findByUserIdAndDeviceId(userId, deviceId)
            .orElseThrow(() -> new BusinessException(NotificationErrorCode.DEVICE_TOKEN_NOT_FOUND));
    deviceToken.deactivate();
    deviceTokenRepository.saveAndFlush(deviceToken);
  }

  /**
   * 같은 Token이 <b>다른 계정에서 활성 상태로</b> 쓰이고 있으면 등록을 거부한다.
   *
   * <p>이전에는 활성 여부를 보지 않아, 계정 A가 해제(NOTI-02)한 뒤에도 A의 비활성 행이 그 {@code token_hash}를 영구 점유했다. {@code
   * token_hash}는 전역 유니크이므로 이후 그 기기에서 로그인하는 다른 계정은 영원히 409를 받고 푸시를 받지 못했다(S15P11B209-862 실기기 실측).
   * 계약(`notification-inbox-contract.md` §3·§0-4)은 "로그아웃 시 해제 → 다음 계정 등록"을 정상 경로로 확정했는데 코드가 그 경로를 막고
   * 있던 것이다.
   *
   * <p>해제하지 않은 활성 등록은 계약대로 계속 409다. 그 상태에서 소유권을 옮기면 이전 사용자에게 갈 알림이 새 사용자 기기로 배달된다.
   */
  private void rejectTokenActiveOnAnotherUser(Long userId, NotificationDeviceToken tokenOwner) {
    if (tokenOwner == null || tokenOwner.getUserId().equals(userId)) {
      return;
    }
    if (tokenOwner.isActive()) {
      throw new BusinessException(NotificationErrorCode.DEVICE_TOKEN_ALREADY_REGISTERED);
    }
  }

  /** 이 Token 행이 요청자의 같은 설치에 대한 등록인지. 그렇다면 평소의 upsert 경로로 갱신한다. */
  private boolean isSameRegistration(
      NotificationDeviceToken tokenOwner, Long userId, String deviceId) {
    return tokenOwner.getUserId().equals(userId) && tokenOwner.getDeviceId().equals(deviceId);
  }

  /**
   * 이미 존재하는 Token 행을 요청자의 등록으로 가져온다.
   *
   * <p>{@code token_hash} 유니크 제약 때문에 행을 새로 만들 수 없어 기존 행을 옮겨 쓴다. 두 경우를 함께 처리한다.
   *
   * <ol>
   *   <li>다른 계정이 <b>해제한</b> Token — 위 {@link #rejectTokenActiveOnAnotherUser}를 통과한 비활성 행이다.
   *   <li>같은 계정이지만 <b>설치 식별자가 다른</b> 경우 — 앱 재설치로 {@code deviceId}는 새로 생겼는데 FCM Token은 그대로인 상황이다.
   *       이전에는 이 경로에서 새 행을 만들려다 유니크 제약을 위반해 500이 났다.
   * </ol>
   */
  private NotificationDeviceToken claimToken(
      NotificationDeviceToken tokenOwner,
      Long userId,
      String deviceId,
      String ciphertext,
      String tokenHash,
      String platform,
      String appVersion) {
    if (!tokenOwner.getUserId().equals(userId)) {
      // Token 원문·hash 전문은 남기지 않는다(계약 §5.4). 소유자 식별자와 hash 앞 8자만 남긴다.
      log.info(
          "해제된 기기 Token의 소유권을 이전합니다. previousUserId={}, newUserId={}, tokenHashPrefix={}",
          tokenOwner.getUserId(),
          userId,
          hashPrefix(tokenHash));
    }
    tokenOwner.transferTo(userId, deviceId);
    tokenOwner.refresh(ciphertext, tokenHash, platform, PUSH_PROVIDER, appVersion);
    return deviceTokenRepository.saveAndFlush(tokenOwner);
  }

  private String hashPrefix(String tokenHash) {
    if (tokenHash == null || tokenHash.length() < HASH_PREFIX_LENGTH) {
      return "unknown";
    }
    return tokenHash.substring(0, HASH_PREFIX_LENGTH);
  }

  private String requireDeviceId(RegisterDeviceTokenRequest request) {
    String deviceId = request == null ? null : trimToNull(request.deviceId());
    if (deviceId == null || deviceId.length() > MAX_DEVICE_ID_LENGTH) {
      throw new BusinessException(NotificationErrorCode.DEVICE_TOKEN_INVALID);
    }
    return deviceId;
  }

  private String requirePlatform(RegisterDeviceTokenRequest request) {
    String platform = trimToNull(request.platform());
    if (platform == null || !ALLOWED_PLATFORMS.contains(platform)) {
      throw new BusinessException(NotificationErrorCode.DEVICE_TOKEN_INVALID);
    }
    return platform;
  }

  private String requirePushToken(RegisterDeviceTokenRequest request) {
    String pushToken = trimToNull(request.pushToken());
    if (pushToken == null) {
      throw new BusinessException(NotificationErrorCode.DEVICE_TOKEN_INVALID);
    }
    return pushToken;
  }

  private String normalizeAppVersion(String appVersion) {
    String normalized = trimToNull(appVersion);
    if (normalized != null && normalized.length() > MAX_APP_VERSION_LENGTH) {
      throw new BusinessException(NotificationErrorCode.DEVICE_TOKEN_INVALID);
    }
    return normalized;
  }

  private String trimToNull(String value) {
    if (value == null) {
      return null;
    }
    String trimmed = value.trim();
    return trimmed.isEmpty() ? null : trimmed;
  }

  private String hash(String pushToken) {
    try {
      byte[] digest =
          MessageDigest.getInstance("SHA-256").digest(pushToken.getBytes(StandardCharsets.UTF_8));
      return HexFormat.of().formatHex(digest);
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 is not available", exception);
    }
  }

  /**
   * 저장 결과를 응답으로 옮긴다.
   *
   * <p>{@code updatedAt}은 Entity가 아니라 서버 수신 시각을 쓴다. DB의 {@code ON UPDATE CURRENT_TIMESTAMP}는 flush
   * 후 Entity에 반영되지 않아 갱신 경로에서 이전 값이 나간다.
   *
   * <p>응답 시각은 UTC ISO-8601(`Z` 접미사)로 나가도록 {@code Instant}를 그대로 쓴다.
   */
  private DeviceTokenResponse response(NotificationDeviceToken deviceToken, boolean registered) {
    return new DeviceTokenResponse(
        deviceToken.getDeviceId(),
        deviceToken.getPlatform(),
        deviceToken.getPushProvider(),
        deviceToken.isActive(),
        registered,
        clock.instant());
  }
}
