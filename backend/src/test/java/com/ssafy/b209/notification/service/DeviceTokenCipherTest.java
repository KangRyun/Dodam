package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.exception.NotificationErrorCode;
import java.util.Base64;
import org.junit.jupiter.api.Test;

/** Push Token 봉인·복원과 키 미구성 시 거부 동작을 검증한다. */
class DeviceTokenCipherTest {

  private static final String KEY = Base64.getEncoder().encodeToString(new byte[32]);

  @Test
  void restoresTheOriginalTokenAfterSealing() {
    DeviceTokenCipher cipher = cipher(KEY);

    String sealed = cipher.encrypt("fcm-registration-token");

    assertThat(sealed).doesNotContain("fcm-registration-token");
    assertThat(cipher.decrypt(sealed)).isEqualTo("fcm-registration-token");
  }

  @Test
  void producesDifferentCiphertextForTheSameTokenSoStoredValuesAreNotComparable() {
    DeviceTokenCipher cipher = cipher(KEY);

    String first = cipher.encrypt("same-token");
    String second = cipher.encrypt("same-token");

    // IV가 매번 새로 생성되므로 암호문으로 동일성을 판단할 수 없고 별도 hash가 필요하다.
    assertThat(first).isNotEqualTo(second);
    assertThat(cipher.decrypt(first)).isEqualTo(cipher.decrypt(second));
  }

  @Test
  void refusesToStoreTokensWhenKeyIsNotConfigured() {
    DeviceTokenCipher cipher = cipher("");

    assertThat(cipher.isConfigured()).isFalse();
    assertError(() -> cipher.encrypt("token"));
  }

  @Test
  void refusesKeysThatAreNotThirtyTwoBytes() {
    DeviceTokenCipher cipher = cipher(Base64.getEncoder().encodeToString(new byte[16]));

    assertThat(cipher.isConfigured()).isFalse();
    assertError(() -> cipher.encrypt("token"));
  }

  @Test
  void refusesKeysThatAreNotBase64() {
    DeviceTokenCipher cipher = cipher("not-base64!!");

    assertThat(cipher.isConfigured()).isFalse();
    assertError(() -> cipher.encrypt("token"));
  }

  @Test
  void refusesTamperedCiphertext() {
    DeviceTokenCipher cipher = cipher(KEY);
    String sealed = cipher.encrypt("fcm-registration-token");
    String tampered = sealed.substring(0, sealed.length() - 4) + "AAAA";

    assertError(() -> cipher.decrypt(tampered));
  }

  private DeviceTokenCipher cipher(String key) {
    DeviceTokenCipherProperties properties = new DeviceTokenCipherProperties();
    properties.setEncryptionKey(key);
    return new DeviceTokenCipher(properties);
  }

  private void assertError(Runnable invocation) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(NotificationErrorCode.DEVICE_TOKEN_STORAGE_UNAVAILABLE));
  }
}
