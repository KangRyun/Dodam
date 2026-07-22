package com.ssafy.b209.auth.token;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.JwtException;

class JwtRefreshTokenDecoderTest {

  private static final String SECRET = "0123456789abcdef0123456789abcdef";
  private static final Instant NOW = Instant.parse("2026-07-22T12:00:00Z");

  @Test
  void acceptsOnlyRefreshTokenAndRestoresFamily() {
    JwtProperties properties =
        new JwtProperties(SECRET, "dodam-api", Duration.ofMinutes(30), Duration.ofDays(14));
    Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
    IssuedTokenPair pair = new JwtTokenIssuer(properties, clock).issue(41L, "family-1");
    JwtRefreshTokenDecoder decoder = new JwtRefreshTokenDecoder(properties, clock);

    VerifiedRefreshToken verified = decoder.decode(pair.refreshToken());

    assertThat(verified).isEqualTo(new VerifiedRefreshToken(41L, "family-1"));
    assertThatThrownBy(() -> decoder.decode(pair.accessToken())).isInstanceOf(JwtException.class);
  }
}
