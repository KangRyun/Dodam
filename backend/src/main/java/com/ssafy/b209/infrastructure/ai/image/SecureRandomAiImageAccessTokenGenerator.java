package com.ssafy.b209.infrastructure.ai.image;

import java.security.SecureRandom;
import java.util.Base64;
import java.util.Objects;

/** {@link SecureRandom}으로 256-bit 일회성 이미지 조회 Token을 생성한다. */
public final class SecureRandomAiImageAccessTokenGenerator implements AiImageAccessTokenGenerator {

  private static final int TOKEN_BYTES = 32;

  private final SecureRandom secureRandom;

  /**
   * Token 생성기를 구성한다.
   *
   * @param secureRandom 암호학적으로 안전한 난수 생성기
   */
  public SecureRandomAiImageAccessTokenGenerator(SecureRandom secureRandom) {
    this.secureRandom = Objects.requireNonNull(secureRandom, "secureRandom must not be null");
  }

  @Override
  public String generate() {
    byte[] bytes = new byte[TOKEN_BYTES];
    secureRandom.nextBytes(bytes);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
  }
}
