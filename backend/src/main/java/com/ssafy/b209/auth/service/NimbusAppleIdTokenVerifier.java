package com.ssafy.b209.auth.service;

import static java.nio.charset.StandardCharsets.UTF_8;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Instant;
import java.util.HexFormat;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

/**
 * Apple 공개 JWK로 Identity Token 서명을 검증하고 필수 OpenID Connect Claim과 nonce를 확인한다.
 *
 * <p>서명 검증 전 Payload를 사용자 신원으로 사용하지 않으며, Token과 raw nonce 원문 또는 Claim 전체를 저장하거나 로그에 기록하지 않는다.
 */
@Component
public class NimbusAppleIdTokenVerifier implements AppleIdTokenVerifier {

  private static final String APPLE_JWK_SET_URI = "https://appleid.apple.com/auth/keys";
  private static final String APPLE_ISSUER = "https://appleid.apple.com";

  private final OAuthProviderProperties properties;
  private final JwtDecoder jwtDecoder;
  private final Clock clock;

  /**
   * Apple 공개 JWK Set을 사용하는 Identity Token 검증기를 구성한다.
   *
   * @param properties Apple Client ID를 포함한 OAuth 검증 설정
   */
  @Autowired
  public NimbusAppleIdTokenVerifier(OAuthProviderProperties properties) {
    this(properties, NimbusJwtDecoder.withJwkSetUri(APPLE_JWK_SET_URI).build(), Clock.systemUTC());
  }

  NimbusAppleIdTokenVerifier(
      OAuthProviderProperties properties, JwtDecoder jwtDecoder, Clock clock) {
    this.properties = properties;
    this.jwtDecoder = jwtDecoder;
    this.clock = clock;
  }

  /**
   * Apple Identity Token의 서명, 발급자, 수신자, 만료, 사용자 식별자와 nonce를 검증한다.
   *
   * @param idToken Sign in with Apple이 발급한 Identity Token
   * @param rawNonce Apple 인증 요청 전에 앱이 생성한 원본 nonce
   * @return 검증된 Apple 사용자 신원
   * @throws BusinessException 설정 누락, Token 검증 실패 또는 Apple JWK 조회 장애인 경우
   */
  @Override
  public VerifiedOAuthIdentity verify(String idToken, String rawNonce) {
    String clientId = requireClientId();
    Jwt jwt;
    try {
      jwt = jwtDecoder.decode(idToken);
    } catch (JwtException exception) {
      AuthErrorCode errorCode =
          hasCause(exception, IOException.class)
              ? AuthErrorCode.OAUTH_PROVIDER_ERROR
              : AuthErrorCode.OAUTH_CREDENTIAL_INVALID;
      throw new BusinessException(errorCode, exception);
    }

    String subject = jwt.getSubject();
    Instant expiresAt = jwt.getExpiresAt();
    if (!APPLE_ISSUER.equals(jwt.getIssuer() == null ? null : jwt.getIssuer().toString())
        || jwt.getAudience() == null
        || !jwt.getAudience().contains(clientId)
        || expiresAt == null
        || !expiresAt.isAfter(Instant.now(clock))
        || !StringUtils.hasText(subject)
        || !nonceMatches(rawNonce, jwt.getClaimAsString("nonce"))) {
      throw new BusinessException(AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
    }

    String email =
        isEmailVerified(jwt.getClaim("email_verified")) ? jwt.getClaimAsString("email") : null;
    return new VerifiedOAuthIdentity(AuthProvider.APPLE, subject, email);
  }

  private String requireClientId() {
    OAuthProviderProperties.Apple apple = properties.apple();
    if (apple == null || !StringUtils.hasText(apple.clientId())) {
      throw new BusinessException(AuthErrorCode.AUTH_CONFIGURATION_INVALID);
    }
    return apple.clientId();
  }

  private boolean nonceMatches(String rawNonce, String tokenNonce) {
    if (!StringUtils.hasText(rawNonce) || !StringUtils.hasText(tokenNonce)) {
      return false;
    }
    String expectedNonce = sha256Hex(rawNonce);
    return MessageDigest.isEqual(expectedNonce.getBytes(UTF_8), tokenNonce.getBytes(UTF_8));
  }

  private String sha256Hex(String value) {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      return HexFormat.of().formatHex(digest.digest(value.getBytes(UTF_8)));
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 algorithm is unavailable", exception);
    }
  }

  private boolean isEmailVerified(Object claim) {
    return Boolean.TRUE.equals(claim)
        || (claim instanceof String text && Boolean.parseBoolean(text));
  }

  private boolean hasCause(Throwable throwable, Class<? extends Throwable> causeType) {
    Throwable current = throwable;
    while (current != null) {
      if (causeType.isInstance(current)) {
        return true;
      }
      current = current.getCause();
    }
    return false;
  }
}
