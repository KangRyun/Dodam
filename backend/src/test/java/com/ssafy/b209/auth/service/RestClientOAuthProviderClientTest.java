package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class RestClientOAuthProviderClientTest {

  private MockRestServiceServer server;
  private RestClientOAuthProviderClient client;

  @BeforeEach
  void setUp() {
    RestClient.Builder builder = RestClient.builder();
    server = MockRestServiceServer.bindTo(builder).build();
    OAuthProviderProperties properties =
        new OAuthProviderProperties(
            new OAuthProviderProperties.Provider(
                "kakao-client", "kakao-secret", "https://app.example/kakao"),
            new OAuthProviderProperties.Provider(
                "google-client", "google-secret", "https://app.example/google"),
            new OAuthProviderProperties.Provider(
                "naver-client", "naver-secret", "https://app.example/naver"),
            java.time.Duration.ofSeconds(3),
            java.time.Duration.ofSeconds(5));
    client = new RestClientOAuthProviderClient(builder.build(), properties);
  }

  @Test
  void usesKakaoIdAndIgnoresUnverifiedEmail() {
    server
        .expect(requestTo("https://kauth.kakao.com/oauth/token"))
        .andExpect(method(HttpMethod.POST))
        .andExpect(content().string(containsString("client_id=kakao-client")))
        .andExpect(content().string(containsString("code=code")))
        .andRespond(
            withSuccess("{\"access_token\":\"provider-token\"}", MediaType.APPLICATION_JSON));
    server
        .expect(requestTo("https://kapi.kakao.com/v2/user/me"))
        .andExpect(header("Authorization", "Bearer provider-token"))
        .andRespond(
            withSuccess(
                "{\"id\":12345,\"kakao_account\":{\"email\":\"unsafe@example.com\","
                    + "\"is_email_valid\":true,\"is_email_verified\":false}}",
                MediaType.APPLICATION_JSON));

    VerifiedOAuthIdentity identity =
        client.verify(
            AuthProvider.KAKAO,
            new OAuthLoginRequest("code", "https://app.example/kakao", null, "device"));

    assertThat(identity.providerSubject()).isEqualTo("12345");
    assertThat(identity.providerEmail()).isNull();
    server.verify();
  }

  @Test
  void usesGoogleSubAndOnlyVerifiedEmail() {
    server
        .expect(requestTo("https://oauth2.googleapis.com/token"))
        .andExpect(method(HttpMethod.POST))
        .andExpect(content().string(containsString("client_secret=google-secret")))
        .andRespond(
            withSuccess("{\"access_token\":\"provider-token\"}", MediaType.APPLICATION_JSON));
    server
        .expect(requestTo("https://openidconnect.googleapis.com/v1/userinfo"))
        .andExpect(header("Authorization", "Bearer provider-token"))
        .andRespond(
            withSuccess(
                "{\"sub\":\"google-sub\",\"email\":\"user@example.com\",\"email_verified\":true}",
                MediaType.APPLICATION_JSON));

    VerifiedOAuthIdentity identity =
        client.verify(
            AuthProvider.GOOGLE,
            new OAuthLoginRequest("code", "https://app.example/google", null, "device"));

    assertThat(identity.providerSubject()).isEqualTo("google-sub");
    assertThat(identity.providerEmail()).isEqualTo("user@example.com");
    server.verify();
  }

  @Test
  void usesNaverResponseIdWithoutTreatingEmailAsIdentity() {
    server
        .expect(requestTo("https://nid.naver.com/oauth2.0/token"))
        .andExpect(method(HttpMethod.POST))
        .andExpect(content().string(containsString("state=csrf-state")))
        .andRespond(
            withSuccess("{\"access_token\":\"provider-token\"}", MediaType.APPLICATION_JSON));
    server
        .expect(requestTo("https://openapi.naver.com/v1/nid/me"))
        .andExpect(header("Authorization", "Bearer provider-token"))
        .andRespond(
            withSuccess(
                "{\"resultcode\":\"00\",\"response\":{\"id\":\"naver-id\","
                    + "\"email\":\"user@example.com\"}}",
                MediaType.APPLICATION_JSON));

    VerifiedOAuthIdentity identity =
        client.verify(
            AuthProvider.NAVER,
            new OAuthLoginRequest("code", "https://app.example/naver", "csrf-state", "device"));

    assertThat(identity.providerSubject()).isEqualTo("naver-id");
    assertThat(identity.providerEmail()).isNull();
    server.verify();
  }
}
