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

/** HS256 서명, 발급자, 만료와 Token 용도를 검증해 Access Token Principal을 복원한다. */
@Component
public class JwtAccessTokenDecoder {

  private static final int MINIMUM_SECRET_BYTES = 32;

  private final JwtProperties properties;
  private final Clock clock;

  /**
   * Access Token Decoder를 구성한다.
   *
   * @param properties 서비스 JWT 서명과 발급자 설정
   * @param clock Token 시간 Claim 검증 기준
   */
  public JwtAccessTokenDecoder(JwtProperties properties, Clock clock) {
    this.properties = properties;
    this.clock = clock;
  }

  /**
   * 서비스 Access JWT를 검증하고 사용자 Principal로 변환한다.
   *
   * @param token Authorization Header에서 분리한 JWT 문자열
   * @return 검증된 사용자 ID를 포함한 Principal
   * @throws JwtException 서명, 발급자, 만료, 용도 또는 Subject가 유효하지 않은 경우
   * @throws BusinessException 서버 JWT 설정이 안전하지 않은 경우
   */
  public AuthenticatedUser decode(String token) {
    Jwt jwt = createDecoder().decode(token);
    try {
      return new AuthenticatedUser(Long.valueOf(jwt.getSubject()));
    } catch (NumberFormatException | NullPointerException exception) {
      throw new JwtException("Access Token subject is invalid", exception);
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
            new JwtClaimValidator<>("token_type", "access"::equals));
    decoder.setJwtValidator(validator);
    return decoder;
  }
}
