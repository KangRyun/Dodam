package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.io.IOException;
import java.time.Clock;
import java.time.Instant;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

/**
 * Google 공개 JWK로 ID Token 서명을 검증하고 필수 OpenID Connect Claim을 확인한다.
 *
 * <p>서명 검증 전 Payload를 사용자 신원으로 사용하지 않으며, Token 원문과 Claim 전체를 저장하거나 로그에 기록하지 않는다.
 */
@Component
public class NimbusGoogleIdTokenVerifier implements GoogleIdTokenVerifier {

  private static final String GOOGLE_JWK_SET_URI = "https://www.googleapis.com/oauth2/v3/certs";
  private static final Set<String> ALLOWED_ISSUERS =
      Set.of("accounts.google.com", "https://accounts.google.com");

  private final OAuthProviderProperties properties;
  private final JwtDecoder jwtDecoder;
  private final Clock clock;

  /**
   * Google 공개 JWK Set을 사용하는 ID Token 검증기를 구성한다.
   *
   * @param properties Google Client ID를 포함한 OAuth 검증 설정
   */
  @Autowired
  public NimbusGoogleIdTokenVerifier(OAuthProviderProperties properties) {
    this(properties, NimbusJwtDecoder.withJwkSetUri(GOOGLE_JWK_SET_URI).build(), Clock.systemUTC());
  }

  NimbusGoogleIdTokenVerifier(
      OAuthProviderProperties properties, JwtDecoder jwtDecoder, Clock clock) {
    this.properties = properties;
    this.jwtDecoder = jwtDecoder;
    this.clock = clock;
  }

  /**
   * Google ID Token의 서명, 발급자, 수신자, 만료와 사용자 식별자를 검증한다.
   *
   * @param idToken 모바일 Google 로그인 SDK가 발급한 ID Token
   * @return 검증된 Google 사용자 신원
   * @throws BusinessException 설정 누락, Token 검증 실패 또는 Google JWK 조회 장애인 경우
   */
  @Override
  public VerifiedOAuthIdentity verify(String idToken) {
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

    String issuer = jwt.getClaimAsString("iss");
    String subject = jwt.getSubject();
    Instant expiresAt = jwt.getExpiresAt();
    if (!ALLOWED_ISSUERS.contains(issuer)
        || jwt.getAudience() == null
        || !jwt.getAudience().contains(clientId)
        || expiresAt == null
        || !expiresAt.isAfter(Instant.now(clock))
        || !StringUtils.hasText(subject)) {
      throw new BusinessException(AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
    }

    String email =
        Boolean.TRUE.equals(jwt.<Boolean>getClaim("email_verified"))
            ? jwt.getClaimAsString("email")
            : null;
    return new VerifiedOAuthIdentity(AuthProvider.GOOGLE, subject, email);
  }

  private String requireClientId() {
    OAuthProviderProperties.Google google = properties.google();
    if (google == null || !StringUtils.hasText(google.clientId())) {
      throw new BusinessException(AuthErrorCode.AUTH_CONFIGURATION_INVALID);
    }
    return google.clientId();
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
