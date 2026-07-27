package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoSettings;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

@MockitoSettings
class RestClientOAuthProviderClientTest {

  @Mock private GoogleIdTokenVerifier googleIdTokenVerifier;
  @Mock private AppleIdTokenVerifier appleIdTokenVerifier;

  private MockRestServiceServer server;
  private RestClientOAuthProviderClient client;

  @BeforeEach
  void setUp() {
    RestClient.Builder builder = RestClient.builder();
    server = MockRestServiceServer.bindTo(builder).build();
    OAuthProviderProperties properties =
        new OAuthProviderProperties(
            new OAuthProviderProperties.Kakao("1234"),
            new OAuthProviderProperties.Google("google-client-id"),
            new OAuthProviderProperties.Apple("com.dodam.app"),
            Duration.ofSeconds(3),
            Duration.ofSeconds(5));
    client =
        new RestClientOAuthProviderClient(
            builder.build(), properties, googleIdTokenVerifier, appleIdTokenVerifier);
  }

  @Test
  void verifiesKakaoTokenAppAndUserBeforeReturningIdentity() {
    server
        .expect(requestTo("https://kapi.kakao.com/v1/user/access_token_info"))
        .andExpect(method(HttpMethod.GET))
        .andExpect(header("Authorization", "Bearer kakao-access-token"))
        .andRespond(
            withSuccess(
                "{\"id\":12345,\"app_id\":1234,\"expires_in\":3600}", MediaType.APPLICATION_JSON));
    server
        .expect(requestTo("https://kapi.kakao.com/v2/user/me"))
        .andExpect(method(HttpMethod.GET))
        .andExpect(header("Authorization", "Bearer kakao-access-token"))
        .andRespond(
            withSuccess(
                "{\"id\":12345,\"kakao_account\":{\"email\":\"user@example.com\","
                    + "\"is_email_valid\":true,\"is_email_verified\":true}}",
                MediaType.APPLICATION_JSON));

    VerifiedOAuthIdentity identity =
        client.verify(
            AuthProvider.KAKAO,
            new OAuthProviderCredential(OAuthCredentialType.ACCESS_TOKEN, "kakao-access-token"));

    assertThat(identity.providerSubject()).isEqualTo("12345");
    assertThat(identity.providerEmail()).isEqualTo("user@example.com");
    server.verify();
  }

  @Test
  void rejectsKakaoTokenIssuedForAnotherApp() {
    server
        .expect(requestTo("https://kapi.kakao.com/v1/user/access_token_info"))
        .andRespond(
            withSuccess(
                "{\"id\":12345,\"app_id\":9999,\"expires_in\":3600}", MediaType.APPLICATION_JSON));

    assertAuthError(
        () ->
            client.verify(
                AuthProvider.KAKAO,
                new OAuthProviderCredential(
                    OAuthCredentialType.ACCESS_TOKEN, "kakao-access-token")),
        AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
    server.verify();
  }

  @Test
  void rejectsKakaoUserDifferentFromTokenOwner() {
    server
        .expect(requestTo("https://kapi.kakao.com/v1/user/access_token_info"))
        .andRespond(
            withSuccess(
                "{\"id\":12345,\"app_id\":1234,\"expires_in\":3600}", MediaType.APPLICATION_JSON));
    server
        .expect(requestTo("https://kapi.kakao.com/v2/user/me"))
        .andRespond(withSuccess("{\"id\":67890}", MediaType.APPLICATION_JSON));

    assertAuthError(
        () ->
            client.verify(
                AuthProvider.KAKAO,
                new OAuthProviderCredential(
                    OAuthCredentialType.ACCESS_TOKEN, "kakao-access-token")),
        AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
    server.verify();
  }

  @Test
  void verifiesNaverUserDirectlyWithAccessToken() {
    server
        .expect(requestTo("https://openapi.naver.com/v1/nid/me"))
        .andExpect(method(HttpMethod.GET))
        .andExpect(header("Authorization", "Bearer naver-access-token"))
        .andRespond(
            withSuccess(
                "{\"resultcode\":\"00\",\"response\":{\"id\":\"naver-id\","
                    + "\"email\":\"user@example.com\"}}",
                MediaType.APPLICATION_JSON));

    VerifiedOAuthIdentity identity =
        client.verify(
            AuthProvider.NAVER,
            new OAuthProviderCredential(OAuthCredentialType.ACCESS_TOKEN, "naver-access-token"));

    assertThat(identity.providerSubject()).isEqualTo("naver-id");
    assertThat(identity.providerEmail()).isNull();
    server.verify();
  }

  @Test
  void mapsProviderClientErrorToInvalidCredential() {
    server
        .expect(requestTo("https://openapi.naver.com/v1/nid/me"))
        .andRespond(withStatus(HttpStatus.UNAUTHORIZED));

    assertAuthError(
        () ->
            client.verify(
                AuthProvider.NAVER,
                new OAuthProviderCredential(
                    OAuthCredentialType.ACCESS_TOKEN, "naver-access-token")),
        AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
    server.verify();
  }

  @Test
  void mapsProviderServerErrorToBadGateway() {
    server.expect(requestTo("https://openapi.naver.com/v1/nid/me")).andRespond(withServerError());

    assertAuthError(
        () ->
            client.verify(
                AuthProvider.NAVER,
                new OAuthProviderCredential(
                    OAuthCredentialType.ACCESS_TOKEN, "naver-access-token")),
        AuthErrorCode.OAUTH_PROVIDER_ERROR);
    server.verify();
  }

  @Test
  void delegatesGoogleIdTokenVerification() {
    OAuthProviderCredential credential =
        new OAuthProviderCredential(OAuthCredentialType.ID_TOKEN, "google-id-token");
    VerifiedOAuthIdentity identity =
        new VerifiedOAuthIdentity(AuthProvider.GOOGLE, "google-sub", "user@example.com");
    when(googleIdTokenVerifier.verify("google-id-token")).thenReturn(identity);

    assertThat(client.verify(AuthProvider.GOOGLE, credential)).isEqualTo(identity);

    verify(googleIdTokenVerifier).verify("google-id-token");
    server.verify();
  }

  @Test
  void delegatesAppleIdTokenAndRawNonceVerification() {
    OAuthProviderCredential credential =
        new OAuthProviderCredential(OAuthCredentialType.ID_TOKEN, "apple-id-token", "raw-nonce");
    VerifiedOAuthIdentity identity =
        new VerifiedOAuthIdentity(
            AuthProvider.APPLE, "apple-subject", "relay@privaterelay.appleid.com");
    when(appleIdTokenVerifier.verify("apple-id-token", "raw-nonce")).thenReturn(identity);

    assertThat(client.verify(AuthProvider.APPLE, credential)).isEqualTo(identity);

    verify(appleIdTokenVerifier).verify("apple-id-token", "raw-nonce");
    server.verify();
  }

  private void assertAuthError(Runnable invocation, AuthErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
