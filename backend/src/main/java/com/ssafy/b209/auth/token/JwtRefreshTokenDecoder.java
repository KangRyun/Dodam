package com.ssafy.b209.auth.token;

import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Component;

/** Refresh JWT의 서명·발급자·만료·용도를 검증하고 Redis 세션 식별 정보를 복원한다. */
@Component
public class JwtRefreshTokenDecoder {

  private static final int MINIMUM_SECRET_BYTES = 32;

  private final JwtProperties properties;
  private final Clock clock;

  /**
   * Refresh Token Decoder를 구성한다.
   *
   * @param properties 서비스 JWT 서명과 발급자 설정
   * @param clock Token 시간 Claim 검증 기준
   */
  public JwtRefreshTokenDecoder(JwtProperties properties, Clock clock) {
    this.properties = properties;
    this.clock = clock;
  }

  /**
   * Refresh JWT를 검증해 사용자와 Token family를 반환한다.
   *
   * @param token 재발급 요청으로 전달된 Refresh JWT 원문
   * @return 검증된 사용자 ID와 family 식별자
   * @throws JwtException JWT 또는 필수 Claim이 유효하지 않은 경우
   * @throws BusinessException 서버 JWT 설정이 안전하지 않은 경우
   */
  public VerifiedRefreshToken decode(String token) {
    Jwt jwt = createDecoder().decode(token);
    try {
      Long userId = Long.valueOf(jwt.getSubject());
      String familyId = jwt.getClaimAsString("family_id");
      if (familyId == null || familyId.isBlank()) {
        throw new JwtException("Refresh Token family is missing");
      }
      return new VerifiedRefreshToken(userId, familyId);
    } catch (NumberFormatException | NullPointerException exception) {
      throw new JwtException("Refresh Token subject is invalid", exception);
    }
  }

  private NimbusJwtDecoder createDecoder() {
    String secret = properties.secret();
    if (secret == null
        || secret.getBytes(StandardCharsets.UTF_8).length < MINIMUM_SECRET_BYTES
        || properties.issuer() == null
        || properties.issuer().isBlank()) {
      throw new BusinessException(AuthErrorCode.AUTH_CONFIGURATION_INVALID);
    }
    SecretKey key = new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
    NimbusJwtDecoder decoder =
        NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
    JwtTimestampValidator timestampValidator = new JwtTimestampValidator(Duration.ofSeconds(60));
    timestampValidator.setClock(clock);
    OAuth2TokenValidator<Jwt> validator =
        new DelegatingOAuth2TokenValidator<>(
            timestampValidator,
            new JwtIssuerValidator(properties.issuer()),
            new JwtClaimValidator<>("token_type", "refresh"::equals));
    decoder.setJwtValidator(validator);
    return decoder;
  }
}
