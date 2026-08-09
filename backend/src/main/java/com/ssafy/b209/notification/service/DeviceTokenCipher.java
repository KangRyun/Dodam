package com.ssafy.b209.notification.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.exception.NotificationErrorCode;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Component;

/**
 * Push 기기 Token을 AES-256-GCM으로 봉인·복원한다.
 *
 * <p>Refresh Token은 검증만 필요해 SHA-256 hash로 저장하지만 Push Token은 발송 시 원문이 필요하므로 복호화 가능한 형태로 보관해야 한다. 저장
 * 형식은 {@code Base64(IV(12) || ciphertext || tag(16))} 한 덩어리이며, IV는 매 암호화마다 새로 만든다. 같은 Token을 다시
 * 등록해도 저장 값이 달라지므로 암호문으로 동일성을 비교하지 않고 별도 SHA-256 hash를 사용한다.
 *
 * <p>키가 구성되지 않은 환경에서는 예외를 던져 등록을 거부한다. 평문 저장으로 후퇴하지 않는다.
 */
@Component
public class DeviceTokenCipher {

  private static final String TRANSFORMATION = "AES/GCM/NoPadding";
  private static final String ALGORITHM = "AES";
  private static final int KEY_LENGTH_BYTES = 32;
  private static final int IV_LENGTH_BYTES = 12;
  private static final int TAG_LENGTH_BITS = 128;

  private final DeviceTokenCipherProperties properties;
  private final SecureRandom secureRandom = new SecureRandom();

  /**
   * 대칭키 설정을 주입받는다.
   *
   * @param properties Base64 AES-256 키를 담은 설정
   */
  public DeviceTokenCipher(DeviceTokenCipherProperties properties) {
    this.properties = properties;
  }

  /**
   * 키가 구성되어 Token을 저장할 수 있는 상태인지 알려준다.
   *
   * @return 32바이트 키가 구성되어 있으면 {@code true}
   */
  public boolean isConfigured() {
    try {
      return readKey().length == KEY_LENGTH_BYTES;
    } catch (RuntimeException exception) {
      return false;
    }
  }

  /**
   * Push Token 원문을 저장 가능한 한 덩어리 문자열로 봉인한다.
   *
   * @param plainToken Push Provider가 발급한 Token 원문
   * @return {@code Base64(IV || ciphertext || tag)}
   * @throws BusinessException 키가 없거나 형식이 잘못된 경우
   */
  public String encrypt(String plainToken) {
    byte[] key = requireKey();
    byte[] iv = new byte[IV_LENGTH_BYTES];
    secureRandom.nextBytes(iv);
    try {
      Cipher cipher = Cipher.getInstance(TRANSFORMATION);
      cipher.init(
          Cipher.ENCRYPT_MODE,
          new SecretKeySpec(key, ALGORITHM),
          new GCMParameterSpec(TAG_LENGTH_BITS, iv));
      byte[] sealed = cipher.doFinal(plainToken.getBytes(StandardCharsets.UTF_8));
      byte[] payload = new byte[iv.length + sealed.length];
      System.arraycopy(iv, 0, payload, 0, iv.length);
      System.arraycopy(sealed, 0, payload, iv.length, sealed.length);
      return Base64.getEncoder().encodeToString(payload);
    } catch (GeneralSecurityException exception) {
      throw new BusinessException(
          NotificationErrorCode.DEVICE_TOKEN_STORAGE_UNAVAILABLE, exception);
    }
  }

  /**
   * 저장된 암호문에서 Push Token 원문을 복원한다.
   *
   * @param ciphertext {@link #encrypt(String)}가 만든 저장 값
   * @return Push Token 원문
   * @throws BusinessException 키가 없거나 암호문이 손상된 경우
   */
  public String decrypt(String ciphertext) {
    byte[] key = requireKey();
    try {
      byte[] payload = Base64.getDecoder().decode(ciphertext);
      byte[] iv = new byte[IV_LENGTH_BYTES];
      System.arraycopy(payload, 0, iv, 0, IV_LENGTH_BYTES);
      Cipher cipher = Cipher.getInstance(TRANSFORMATION);
      cipher.init(
          Cipher.DECRYPT_MODE,
          new SecretKeySpec(key, ALGORITHM),
          new GCMParameterSpec(TAG_LENGTH_BITS, iv));
      byte[] plain = cipher.doFinal(payload, IV_LENGTH_BYTES, payload.length - IV_LENGTH_BYTES);
      return new String(plain, StandardCharsets.UTF_8);
    } catch (GeneralSecurityException | IllegalArgumentException exception) {
      throw new BusinessException(
          NotificationErrorCode.DEVICE_TOKEN_STORAGE_UNAVAILABLE, exception);
    }
  }

  private byte[] requireKey() {
    byte[] key = readKey();
    if (key.length != KEY_LENGTH_BYTES) {
      throw new BusinessException(NotificationErrorCode.DEVICE_TOKEN_STORAGE_UNAVAILABLE);
    }
    return key;
  }

  private byte[] readKey() {
    String configured = properties.getEncryptionKey();
    if (configured == null || configured.isBlank()) {
      throw new BusinessException(NotificationErrorCode.DEVICE_TOKEN_STORAGE_UNAVAILABLE);
    }
    try {
      return Base64.getDecoder().decode(configured.trim());
    } catch (IllegalArgumentException exception) {
      throw new BusinessException(
          NotificationErrorCode.DEVICE_TOKEN_STORAGE_UNAVAILABLE, exception);
    }
  }
}
