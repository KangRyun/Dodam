package com.ssafy.b209.auth.token;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

class JwtTokenIssuerTest {

  private static final Instant NOW = Instant.parse("2026-07-22T12:00:00Z");
  private static final String SECRET = "0123456789abcdef0123456789abcdef";

  @Test
  void issuesAccessAndRefreshTokensWithSeparatedPurposes() {
    JwtTokenIssuer issuer =
        new JwtTokenIssuer(
            new JwtProperties(SECRET, "dodam-api", Duration.ofMinutes(30), Duration.ofDays(14)),
            Clock.fixed(NOW, ZoneOffset.UTC));

    IssuedTokenPair pair = issuer.issue(41L);

    NimbusJwtDecoder decoder =
        NimbusJwtDecoder.withSecretKey(
                new SecretKeySpec(
                    SECRET.getBytes(java.nio.charset.StandardCharsets.UTF_8), "HmacSHA256"))
            .macAlgorithm(MacAlgorithm.HS256)
            .build();
    JwtTimestampValidator timestampValidator = new JwtTimestampValidator(Duration.ZERO);
    timestampValidator.setClock(Clock.fixed(NOW, ZoneOffset.UTC));
    decoder.setJwtValidator(timestampValidator);
    Jwt access = decoder.decode(pair.accessToken());
    Jwt refresh = decoder.decode(pair.refreshToken());
    assertThat(access.getSubject()).isEqualTo("41");
    assertThat(access.getClaimAsString("token_type")).isEqualTo("access");
    assertThat(access.getExpiresAt()).isEqualTo(NOW.plus(Duration.ofMinutes(30)));
    assertThat(refresh.getSubject()).isEqualTo("41");
    assertThat(refresh.getClaimAsString("token_type")).isEqualTo("refresh");
    assertThat(refresh.getExpiresAt()).isEqualTo(NOW.plus(Duration.ofDays(14)));
    assertThat(pair.accessTokenExpiresInSeconds()).isEqualTo(1800);
    assertThat(pair.refreshTokenExpiresInSeconds()).isEqualTo(1209600);
  }

  @Test
  void rejectsMissingOrShortSigningSecretWithoutUsingFallback() {
    JwtTokenIssuer missing =
        new JwtTokenIssuer(
            new JwtProperties("", "dodam-api", Duration.ofMinutes(30), Duration.ofDays(14)),
            Clock.fixed(NOW, ZoneOffset.UTC));
    JwtTokenIssuer shortSecret =
        new JwtTokenIssuer(
            new JwtProperties(
                "too-short", "dodam-api", Duration.ofMinutes(30), Duration.ofDays(14)),
            Clock.fixed(NOW, ZoneOffset.UTC));

    assertThatThrownBy(() -> missing.issue(1L))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.AUTH_CONFIGURATION_INVALID));
    assertThatThrownBy(() -> shortSecret.issue(1L))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.AUTH_CONFIGURATION_INVALID));
  }
}
