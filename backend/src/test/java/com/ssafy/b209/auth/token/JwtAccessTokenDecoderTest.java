package com.ssafy.b209.auth.token;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.JwtException;

class JwtAccessTokenDecoderTest {

  private static final String SECRET = "0123456789abcdef0123456789abcdef";
  private static final Instant NOW = Instant.parse("2026-07-22T12:00:00Z");

  @Test
  void decodesValidAccessTokenToUserId() {
    JwtProperties properties =
        new JwtProperties(SECRET, "dodam-api", Duration.ofMinutes(30), Duration.ofDays(14));
    Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
    String accessToken = new JwtTokenIssuer(properties, clock).issue(41L).accessToken();

    AuthenticatedUser user = new JwtAccessTokenDecoder(properties, clock).decode(accessToken);

    assertThat(user.userId()).isEqualTo(41L);
  }

  @Test
  void rejectsRefreshTokenAtAccessAuthenticationBoundary() {
    JwtProperties properties =
        new JwtProperties(SECRET, "dodam-api", Duration.ofMinutes(30), Duration.ofDays(14));
    Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
    String refreshToken = new JwtTokenIssuer(properties, clock).issue(41L).refreshToken();

    assertThatThrownBy(() -> new JwtAccessTokenDecoder(properties, clock).decode(refreshToken))
        .isInstanceOf(JwtException.class);
  }

  @Test
  void rejectsExpiredAccessToken() {
    JwtProperties properties =
        new JwtProperties(SECRET, "dodam-api", Duration.ofMinutes(30), Duration.ofDays(14));
    String expiredToken =
        new JwtTokenIssuer(properties, Clock.fixed(NOW.minus(Duration.ofHours(1)), ZoneOffset.UTC))
            .issue(41L)
            .accessToken();

    assertThatThrownBy(
            () ->
                new JwtAccessTokenDecoder(properties, Clock.fixed(NOW, ZoneOffset.UTC))
                    .decode(expiredToken))
        .isInstanceOf(JwtException.class);
  }
}
