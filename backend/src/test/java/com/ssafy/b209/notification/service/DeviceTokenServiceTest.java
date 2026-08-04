package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.domain.NotificationDeviceToken;
import com.ssafy.b209.notification.dto.request.RegisterDeviceTokenRequest;
import com.ssafy.b209.notification.dto.response.DeviceTokenResponse;
import com.ssafy.b209.notification.exception.NotificationErrorCode;
import com.ssafy.b209.notification.repository.NotificationDeviceTokenRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** 설치 식별자 기준 upsert, Token 재사용 거부, 해제 동작을 검증한다. */
@ExtendWith(MockitoExtension.class)
class DeviceTokenServiceTest {

  private static final Long USER_ID = 41L;
  private static final Long OTHER_USER_ID = 42L;
  private static final String DEVICE_ID = "installation-uuid";
  private static final Instant NOW = Instant.parse("2026-07-26T12:00:00Z");

  @Mock private NotificationDeviceTokenRepository deviceTokenRepository;

  private DeviceTokenService service;

  @BeforeEach
  void setUp() {
    DeviceTokenCipherProperties properties = new DeviceTokenCipherProperties();
    properties.setEncryptionKey(Base64.getEncoder().encodeToString(new byte[32]));
    service =
        new DeviceTokenService(
            deviceTokenRepository,
            new DeviceTokenCipher(properties),
            Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void registersNewDeviceTokenWithoutExposingTheTokenValue() {
    given(deviceTokenRepository.findByTokenHash(any())).willReturn(Optional.empty());
    given(deviceTokenRepository.findByUserIdAndDeviceId(USER_ID, DEVICE_ID))
        .willReturn(Optional.empty());
    given(deviceTokenRepository.saveAndFlush(any(NotificationDeviceToken.class)))
        .willAnswer(invocation -> invocation.getArgument(0));

    DeviceTokenResponse response = service.register(USER_ID, request("fcm-token", "ANDROID"));

    ArgumentCaptor<NotificationDeviceToken> captor =
        ArgumentCaptor.forClass(NotificationDeviceToken.class);
    verify(deviceTokenRepository).saveAndFlush(captor.capture());
    NotificationDeviceToken saved = captor.getValue();
    assertThat(saved.getUserId()).isEqualTo(USER_ID);
    assertThat(saved.getDeviceId()).isEqualTo(DEVICE_ID);
    assertThat(saved.getPlatform()).isEqualTo("ANDROID");
    assertThat(saved.getPushProvider()).isEqualTo("FCM");
    assertThat(saved.isActive()).isTrue();
    assertThat(saved.getTokenHash()).hasSize(64);
    assertThat(saved.getTokenCiphertext()).doesNotContain("fcm-token");
    assertThat(response.registered()).isTrue();
    // 응답 시각은 UTC instant 그대로다. 타임존 표기 없는 벽시계로 내보내면 클라이언트가 자기 지역 시각으로 읽는다.
    assertThat(response.updatedAt()).isEqualTo(NOW);
  }

  @Test
  void replacesStoredTokenForTheSameDeviceInsteadOfAddingRows() {
    NotificationDeviceToken existing = existingToken();
    existing.deactivate();
    given(deviceTokenRepository.findByTokenHash(any())).willReturn(Optional.empty());
    given(deviceTokenRepository.findByUserIdAndDeviceId(USER_ID, DEVICE_ID))
        .willReturn(Optional.of(existing));
    given(deviceTokenRepository.saveAndFlush(existing)).willReturn(existing);

    DeviceTokenResponse response = service.register(USER_ID, request("rotated-token", "IOS"));

    assertThat(response.registered()).isFalse();
    assertThat(existing.getPlatform()).isEqualTo("IOS");
    // 해제 후 재로그인이 정상 경로이므로 재등록은 다시 활성으로 되돌린다.
    assertThat(existing.isActive()).isTrue();
    assertThat(existing.getTokenCiphertext()).doesNotContain("rotated-token");
  }

  @Test
  void rejectsTokenAlreadyRegisteredToAnotherAccount() {
    NotificationDeviceToken otherUsersToken =
        NotificationDeviceToken.register(
            OTHER_USER_ID,
            "other-device",
            "ciphertext",
            "hash",
            "ANDROID",
            "FCM",
            null,
            LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
    given(deviceTokenRepository.findByTokenHash(any())).willReturn(Optional.of(otherUsersToken));

    assertError(
        () -> service.register(USER_ID, request("fcm-token", "ANDROID")),
        NotificationErrorCode.DEVICE_TOKEN_ALREADY_REGISTERED);

    verify(deviceTokenRepository, never()).saveAndFlush(any(NotificationDeviceToken.class));
  }

  @Test
  void claimsTokenReleasedByAnotherAccountInsteadOfBlockingItForever() {
    // 계정 A가 NOTI-02로 해제한 뒤 계정 B가 같은 기기에서 등록하는 경로다. 계약 §3이 정상 경로로
    // 확정했는데, 활성 여부를 보지 않던 이전 구현은 A의 비활성 행이 token_hash를 영구 점유해
    // B를 영원히 409로 막았다(S15P11B209-862).
    NotificationDeviceToken releasedToken =
        NotificationDeviceToken.register(
            OTHER_USER_ID,
            "other-device",
            "old-ciphertext",
            "hash",
            "ANDROID",
            "FCM",
            "0.9.0",
            LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
    releasedToken.deactivate();
    given(deviceTokenRepository.findByTokenHash(any())).willReturn(Optional.of(releasedToken));
    given(deviceTokenRepository.saveAndFlush(releasedToken)).willReturn(releasedToken);

    DeviceTokenResponse response = service.register(USER_ID, request("fcm-token", "ANDROID"));

    assertThat(response.active()).isTrue();
    assertThat(response.registered()).isTrue();
    assertThat(releasedToken.getUserId()).isEqualTo(USER_ID);
    assertThat(releasedToken.getDeviceId()).isEqualTo(DEVICE_ID);
    assertThat(releasedToken.isActive()).isTrue();
    assertThat(releasedToken.getAppVersion()).isEqualTo("1.0.0");
    // 행을 새로 만들지 않는다. token_hash 가 전역 유니크라 두 행이 공존할 수 없다.
    verify(deviceTokenRepository, never()).findByUserIdAndDeviceId(any(), any());
  }

  @Test
  void keepsRejectingTokenStillActiveOnAnotherAccount() {
    // 해제하지 않고 계정만 전환한 경우다. 계약 §3이 소유권 자동 이전을 금지했으므로 그대로 409다.
    NotificationDeviceToken activeToken =
        NotificationDeviceToken.register(
            OTHER_USER_ID,
            "other-device",
            "ciphertext",
            "hash",
            "ANDROID",
            "FCM",
            null,
            LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
    given(deviceTokenRepository.findByTokenHash(any())).willReturn(Optional.of(activeToken));

    assertError(
        () -> service.register(USER_ID, request("fcm-token", "ANDROID")),
        NotificationErrorCode.DEVICE_TOKEN_ALREADY_REGISTERED);

    assertThat(activeToken.getUserId()).isEqualTo(OTHER_USER_ID);
    verify(deviceTokenRepository, never()).saveAndFlush(any(NotificationDeviceToken.class));
  }

  @Test
  void movesOwnTokenToTheNewInstallationIdentifierWithoutViolatingTheHashConstraint() {
    // 앱을 재설치하면 deviceId 는 새로 생기는데 FCM Token 은 그대로일 수 있다. 이전 구현은 이때
    // 새 행을 만들려다 token_hash 유니크 제약을 위반했다.
    NotificationDeviceToken sameUsersToken =
        NotificationDeviceToken.register(
            USER_ID,
            "previous-installation",
            "old-ciphertext",
            "hash",
            "ANDROID",
            "FCM",
            "0.9.0",
            LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
    given(deviceTokenRepository.findByTokenHash(any())).willReturn(Optional.of(sameUsersToken));
    given(deviceTokenRepository.saveAndFlush(sameUsersToken)).willReturn(sameUsersToken);

    DeviceTokenResponse response = service.register(USER_ID, request("fcm-token", "ANDROID"));

    assertThat(response.deviceId()).isEqualTo(DEVICE_ID);
    assertThat(sameUsersToken.getDeviceId()).isEqualTo(DEVICE_ID);
    assertThat(sameUsersToken.getUserId()).isEqualTo(USER_ID);
    verify(deviceTokenRepository, never()).findByUserIdAndDeviceId(any(), any());
  }

  @Test
  void rejectsMissingBodyBlankFieldsAndUnknownPlatformWithTheSameCode() {
    assertError(() -> service.register(USER_ID, null), NotificationErrorCode.DEVICE_TOKEN_INVALID);
    assertError(
        () -> service.register(USER_ID, request("fcm-token", "ANDROID", "  ")),
        NotificationErrorCode.DEVICE_TOKEN_INVALID);
    assertError(
        () -> service.register(USER_ID, new RegisterDeviceTokenRequest(DEVICE_ID, "PC", "t", null)),
        NotificationErrorCode.DEVICE_TOKEN_INVALID);
    assertError(
        () ->
            service.register(
                USER_ID, new RegisterDeviceTokenRequest(DEVICE_ID, "ANDROID", " ", null)),
        NotificationErrorCode.DEVICE_TOKEN_INVALID);
    assertError(
        () ->
            service.register(
                USER_ID, new RegisterDeviceTokenRequest(DEVICE_ID, "ANDROID", "t", "v".repeat(21))),
        NotificationErrorCode.DEVICE_TOKEN_INVALID);

    verify(deviceTokenRepository, never()).saveAndFlush(any(NotificationDeviceToken.class));
  }

  @Test
  void deactivatesDeviceTokenOnReleaseWithoutDeletingTheRow() {
    NotificationDeviceToken existing = existingToken();
    given(deviceTokenRepository.findByUserIdAndDeviceId(USER_ID, DEVICE_ID))
        .willReturn(Optional.of(existing));
    given(deviceTokenRepository.saveAndFlush(existing)).willReturn(existing);

    service.release(USER_ID, DEVICE_ID);

    assertThat(existing.isActive()).isFalse();
    verify(deviceTokenRepository, never()).delete(any());
  }

  @Test
  void reportsMissingDeviceOnRelease() {
    given(deviceTokenRepository.findByUserIdAndDeviceId(USER_ID, DEVICE_ID))
        .willReturn(Optional.empty());

    assertError(
        () -> service.release(USER_ID, DEVICE_ID), NotificationErrorCode.DEVICE_TOKEN_NOT_FOUND);
  }

  private NotificationDeviceToken existingToken() {
    return NotificationDeviceToken.register(
        USER_ID,
        DEVICE_ID,
        "old-ciphertext",
        "old-hash",
        "ANDROID",
        "FCM",
        "1.0.0",
        LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
  }

  private RegisterDeviceTokenRequest request(String pushToken, String platform) {
    return new RegisterDeviceTokenRequest(DEVICE_ID, platform, pushToken, "1.0.0");
  }

  private RegisterDeviceTokenRequest request(String pushToken, String platform, String deviceId) {
    return new RegisterDeviceTokenRequest(deviceId, platform, pushToken, "1.0.0");
  }

  private void assertError(Runnable invocation, NotificationErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
