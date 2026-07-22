package com.ssafy.b209.auth.token;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.stereotype.Component;

/** 서비스가 소유한 HS256 Secret으로 목적이 분리된 Access·Refresh JWT를 발급한다. */
@Component
public class JwtTokenIssuer {

  private static final int MINIMUM_SECRET_BYTES = 32;

  private final JwtProperties properties;
  private final Clock clock;

  /**
   * JWT 발급기를 구성한다.
   *
   * @param properties 서명 Secret과 Token 만료 정책
   * @param clock 발급·만료 시각 계산에 사용하는 Clock
   */
  public JwtTokenIssuer(JwtProperties properties, Clock clock) {
    this.properties = properties;
    this.clock = clock;
  }

  /**
   * 사용자 ID를 Subject로 하는 Access·Refresh JWT를 각각 발급한다.
   *
   * @param userId 인증을 마친 서비스 사용자 ID
   * @return 용도와 만료 시간이 분리된 Token 묶음
   * @throws BusinessException Secret이 없거나 HS256 최소 길이를 충족하지 못한 경우
   */
  public IssuedTokenPair issue(Long userId) {
    JwtEncoder encoder = createEncoder();
    Instant issuedAt = clock.instant();
    String accessToken =
        encode(encoder, userId, "access", issuedAt, issuedAt.plus(properties.accessTokenTtl()));
    String refreshToken =
        encode(encoder, userId, "refresh", issuedAt, issuedAt.plus(properties.refreshTokenTtl()));
    return new IssuedTokenPair(
        accessToken,
        properties.accessTokenTtl().toSeconds(),
        refreshToken,
        properties.refreshTokenTtl().toSeconds());
  }

  /**
   * 일회성 authorization code를 사용하기 전에 JWT 발급 설정이 안전한지 확인한다.
   *
   * @throws BusinessException Secret 또는 만료 정책이 누락되거나 안전하지 않은 경우
   */
  public void validateConfiguration() {
    createEncoder();
  }

  private JwtEncoder createEncoder() {
    String secret = properties.secret();
    if (secret == null
        || secret.getBytes(StandardCharsets.UTF_8).length < MINIMUM_SECRET_BYTES
        || properties.issuer() == null
        || properties.issuer().isBlank()
        || properties.accessTokenTtl() == null
        || properties.accessTokenTtl().isNegative()
        || properties.accessTokenTtl().isZero()
        || properties.refreshTokenTtl() == null
        || properties.refreshTokenTtl().isNegative()
        || properties.refreshTokenTtl().isZero()) {
      throw new BusinessException(AuthErrorCode.AUTH_CONFIGURATION_INVALID);
    }
    SecretKey key = new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
    return new NimbusJwtEncoder(new ImmutableSecret<>(key));
  }

  private String encode(
      JwtEncoder encoder, Long userId, String tokenType, Instant issuedAt, Instant expiresAt) {
    JwtClaimsSet claims =
        JwtClaimsSet.builder()
            .issuer(properties.issuer())
            .subject(userId.toString())
            .issuedAt(issuedAt)
            .expiresAt(expiresAt)
            .id(UUID.randomUUID().toString())
            .claim("token_type", tokenType)
            .build();
    JwsHeader headers = JwsHeader.with(MacAlgorithm.HS256).type("JWT").build();
    return encoder.encode(JwtEncoderParameters.from(headers, claims)).getTokenValue();
  }
}
