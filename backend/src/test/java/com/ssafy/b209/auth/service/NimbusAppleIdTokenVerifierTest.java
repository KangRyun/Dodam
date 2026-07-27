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
class NimbusAppleIdTokenVerifierTest {

  private static final Instant NOW = Instant.parse("2026-07-27T03:00:00Z");
  private static final String RAW_NONCE = "raw-nonce";
  private static final String HASHED_NONCE =
      "2c5d107938053a2275f022c153c9a71f65ee07754b8bca543ee97a0c3cc66990";

  @Mock private JwtDecoder jwtDecoder;

  private NimbusAppleIdTokenVerifier verifier;

  @BeforeEach
  void setUp() {
    verifier =
        new NimbusAppleIdTokenVerifier(
            properties("com.dodam.app"), jwtDecoder, Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void returnsAppleIdentityFromValidIdTokenAndRawNonce() {
    when(jwtDecoder.decode("apple-id-token"))
        .thenReturn(
            validJwt(
                builder ->
                    builder
                        .claim("email", "relay@privaterelay.appleid.com")
                        .claim("email_verified", "true")));

    VerifiedOAuthIdentity identity = verifier.verify("apple-id-token", RAW_NONCE);

    assertThat(identity.provider()).isEqualTo(AuthProvider.APPLE);
    assertThat(identity.providerSubject()).isEqualTo("apple-subject");
    assertThat(identity.providerEmail()).isEqualTo("relay@privaterelay.appleid.com");
  }

  @Test
  void acceptsBooleanEmailVerificationClaim() {
    when(jwtDecoder.decode("apple-id-token"))
        .thenReturn(
            validJwt(
                builder ->
                    builder.claim("email", "user@example.com").claim("email_verified", true)));

    assertThat(verifier.verify("apple-id-token", RAW_NONCE).providerEmail())
        .isEqualTo("user@example.com");
  }

  @Test
  void ignoresEmailWhenAppleDidNotVerifyIt() {
    when(jwtDecoder.decode("apple-id-token"))
        .thenReturn(
            validJwt(
                builder ->
                    builder.claim("email", "unsafe@example.com").claim("email_verified", "false")));

    assertThat(verifier.verify("apple-id-token", RAW_NONCE).providerEmail()).isNull();
  }

  @Test
  void rejectsUnexpectedIssuer() {
    assertInvalidClaims(builder -> builder.issuer("https://issuer.example"), RAW_NONCE);
  }

  @Test
  void rejectsAudienceWithoutConfiguredClientId() {
    assertInvalidClaims(builder -> builder.audience(List.of("another-client-id")), RAW_NONCE);
  }

  @Test
  void rejectsExpiredIdToken() {
    assertInvalidClaims(builder -> builder.expiresAt(NOW.minusSeconds(1)), RAW_NONCE);
  }

  @Test
  void rejectsBlankSubject() {
    assertInvalidClaims(builder -> builder.subject(" "), RAW_NONCE);
  }

  @Test
  void rejectsRawNonceThatDoesNotMatchTokenClaim() {
    assertInvalidClaims(builder -> {}, "another-raw-nonce");
  }

  @Test
  void rejectsMissingNonceClaim() {
    assertInvalidClaims(builder -> builder.claim("nonce", null), RAW_NONCE);
  }

  @Test
  void mapsDecoderValidationFailureToInvalidCredential() {
    when(jwtDecoder.decode("apple-id-token")).thenThrow(new JwtException("invalid token"));

    assertAuthError(
        () -> verifier.verify("apple-id-token", RAW_NONCE), AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
  }

  @Test
  void mapsJwkNetworkFailureToProviderError() {
    when(jwtDecoder.decode("apple-id-token"))
        .thenThrow(new JwtException("jwk unavailable", new IOException("network unavailable")));

    assertAuthError(
        () -> verifier.verify("apple-id-token", RAW_NONCE), AuthErrorCode.OAUTH_PROVIDER_ERROR);
  }

  @Test
  void rejectsMissingClientIdBeforeDecodingToken() {
    NimbusAppleIdTokenVerifier unconfigured =
        new NimbusAppleIdTokenVerifier(
            properties(" "), jwtDecoder, Clock.fixed(NOW, ZoneOffset.UTC));

    assertAuthError(
        () -> unconfigured.verify("apple-id-token", RAW_NONCE),
        AuthErrorCode.AUTH_CONFIGURATION_INVALID);
    verifyNoInteractions(jwtDecoder);
  }

  private void assertInvalidClaims(Consumer<Jwt.Builder> invalidChange, String rawNonce) {
    Jwt.Builder builder = validJwtBuilder();
    invalidChange.accept(builder);
    when(jwtDecoder.decode("apple-id-token")).thenReturn(builder.build());

    assertAuthError(
        () -> verifier.verify("apple-id-token", rawNonce), AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
  }

  private Jwt validJwt(Consumer<Jwt.Builder> customizer) {
    Jwt.Builder builder = validJwtBuilder();
    customizer.accept(builder);
    return builder.build();
  }

  private Jwt.Builder validJwtBuilder() {
    return Jwt.withTokenValue("apple-id-token")
        .header("alg", "RS256")
        .issuer("https://appleid.apple.com")
        .audience(List.of("com.dodam.app"))
        .subject("apple-subject")
        .issuedAt(NOW.minusSeconds(60))
        .expiresAt(NOW.plusSeconds(300))
        .claim("nonce", HASHED_NONCE);
  }

  private OAuthProviderProperties properties(String clientId) {
    return new OAuthProviderProperties(
        new OAuthProviderProperties.Kakao("1234"),
        new OAuthProviderProperties.Google("google-client-id"),
        new OAuthProviderProperties.Apple(clientId),
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
