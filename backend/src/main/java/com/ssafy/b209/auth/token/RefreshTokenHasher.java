package com.ssafy.b209.auth.token;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import org.springframework.stereotype.Component;

/** Redis 유출 시 Token 원문이 노출되지 않도록 Refresh Token의 SHA-256 hash를 계산한다. */
@Component
public class RefreshTokenHasher {

  /**
   * Refresh Token을 고정 길이 소문자 16진수 SHA-256 hash로 변환한다.
   *
   * @param refreshToken Client가 보유한 Refresh Token 원문
   * @return Redis 비교에 사용할 SHA-256 hash
   */
  public String hash(String refreshToken) {
    try {
      byte[] digest =
          MessageDigest.getInstance("SHA-256")
              .digest(refreshToken.getBytes(StandardCharsets.UTF_8));
      return HexFormat.of().formatHex(digest);
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 is not available", exception);
    }
  }
}
