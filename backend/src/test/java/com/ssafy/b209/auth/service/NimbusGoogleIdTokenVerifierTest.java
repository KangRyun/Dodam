package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.io.IOException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.function.Consumer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;

@ExtendWith(MockitoExtension.class)
class NimbusGoogleIdTokenVerifierTest {

  private static final Instant NOW = Instant.parse("2026-07-23T09:00:00Z");

  @Mock private JwtDecoder jwtDecoder;

  private NimbusGoogleIdTokenVerifier verifier;

  @BeforeEach
  void setUp() {
    verifier =
        new NimbusGoogleIdTokenVerifier(
            properties("google-client-id"), jwtDecoder, Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void returnsGoogleIdentityFromValidIdToken() {
    when(jwtDecoder.decode("google-id-token"))
        .thenReturn(
            jwt(
                builder ->
                    builder
                        .issuer("https://accounts.google.com")
                        .audience(List.of("google-client-id"))
                        .subject("google-sub")
                        .expiresAt(NOW.plusSeconds(300))
                        .claim("email", "user@example.com")
                        .claim("email_verified", true)));

    VerifiedOAuthIdentity identity = verifier.verify("google-id-token");

    assertThat(identity.provider()).isEqualTo(AuthProvider.GOOGLE);
    assertThat(identity.providerSubject()).isEqualTo("google-sub");
    assertThat(identity.providerEmail()).isEqualTo("user@example.com");
  }

  @Test
  void ignoresEmailWhenGoogleDidNotVerifyIt() {
    when(jwtDecoder.decode("google-id-token"))
        .thenReturn(
            jwt(
                builder ->
                    builder
                        .issuer("accounts.google.com")
                        .audience(List.of("google-client-id"))
                        .subject("google-sub")
                        .expiresAt(NOW.plusSeconds(300))
                        .claim("email", "unsafe@example.com")
                        .claim("email_verified", false)));

    assertThat(verifier.verify("google-id-token").providerEmail()).isNull();
  }

  @Test
  void rejectsUnexpectedIssuer() {
    assertInvalidClaims(builder -> builder.issuer("https://issuer.example"));
  }

  @Test
  void rejectsAudienceWithoutConfiguredClientId() {
    assertInvalidClaims(builder -> builder.audience(List.of("another-client-id")));
  }

  @Test
  void rejectsExpiredIdToken() {
    assertInvalidClaims(builder -> builder.expiresAt(NOW.minusSeconds(1)));
  }

  @Test
  void rejectsBlankSubject() {
    assertInvalidClaims(builder -> builder.subject(" "));
  }

  @Test
  void mapsDecoderValidationFailureToInvalidCredential() {
    when(jwtDecoder.decode("google-id-token")).thenThrow(new JwtException("invalid token"));

    assertAuthError(
        () -> verifier.verify("google-id-token"), AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
  }

  @Test
  void mapsJwkNetworkFailureToProviderError() {
    when(jwtDecoder.decode("google-id-token"))
        .thenThrow(new JwtException("jwk unavailable", new IOException("network unavailable")));

    assertAuthError(() -> verifier.verify("google-id-token"), AuthErrorCode.OAUTH_PROVIDER_ERROR);
  }

  @Test
  void rejectsMissingClientIdBeforeDecodingToken() {
    NimbusGoogleIdTokenVerifier unconfigured =
        new NimbusGoogleIdTokenVerifier(
            properties(" "), jwtDecoder, Clock.fixed(NOW, ZoneOffset.UTC));

    assertAuthError(
        () -> unconfigured.verify("google-id-token"), AuthErrorCode.AUTH_CONFIGURATION_INVALID);
    verifyNoInteractions(jwtDecoder);
  }

  private void assertInvalidClaims(Consumer<Jwt.Builder> invalidChange) {
    Jwt.Builder builder =
        Jwt.withTokenValue("google-id-token")
            .header("alg", "RS256")
            .issuer("https://accounts.google.com")
            .audience(List.of("google-client-id"))
            .subject("google-sub")
            .issuedAt(NOW.minusSeconds(60))
            .expiresAt(NOW.plusSeconds(300));
    invalidChange.accept(builder);
    when(jwtDecoder.decode("google-id-token")).thenReturn(builder.build());

    assertAuthError(
        () -> verifier.verify("google-id-token"), AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
  }

  private Jwt jwt(Consumer<Jwt.Builder> customizer) {
    Jwt.Builder builder =
        Jwt.withTokenValue("google-id-token").header("alg", "RS256").issuedAt(NOW.minusSeconds(60));
    customizer.accept(builder);
    return builder.build();
  }

  private OAuthProviderProperties properties(String clientId) {
    return new OAuthProviderProperties(
        new OAuthProviderProperties.Kakao("1234"),
        new OAuthProviderProperties.Google(clientId),
        new OAuthProviderProperties.Apple("com.dodam.app"),
        Duration.ofSeconds(3),
        Duration.ofSeconds(5));
  }

  private void assertAuthError(Runnable invocation, AuthErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
