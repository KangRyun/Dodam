package com.ssafy.b209.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.service.OAuthProviderClient;
import com.ssafy.b209.auth.service.RefreshTokenRotationResult;
import com.ssafy.b209.auth.service.RefreshTokenSessionStore;
import com.ssafy.b209.auth.service.VerifiedOAuthIdentity;
import com.ssafy.b209.auth.token.RefreshTokenHasher;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@AutoConfigureMockMvc
@TestPropertySource(
    properties = {
      "app.auth.jwt.secret=0123456789abcdef0123456789abcdef",
      "app.auth.filter.legacy-header-enabled=false"
    })
class OAuthAuthenticationFlowIntegrationTest extends IntegrationTestSupport {

  private static final String DEVICE_ID = "integration-device-001";
  private static final String PROVIDER_SUBJECT = "kakao-integration-user";

  @Autowired private MockMvc mockMvc;
  @Autowired private ObjectMapper objectMapper;
  @Autowired private JdbcTemplate jdbcTemplate;

  @MockitoBean private OAuthProviderClient providerClient;
  @MockitoBean private RefreshTokenSessionStore sessionStore;

  @BeforeEach
  void setUp() {
    when(providerClient.verify(eq(AuthProvider.KAKAO), any()))
        .thenReturn(new VerifiedOAuthIdentity(AuthProvider.KAKAO, PROVIDER_SUBJECT, null));
  }

  @Test
  void oauthLoginPersistsAccountAndAccessTokenAuthenticatesUser() throws Exception {
    JsonNode loginResponse = login();
    long userId = loginResponse.at("/data/user/userId").asLong();
    String accessToken = loginResponse.at("/data/accessToken").asText();

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT provider, provider_subject FROM auth_accounts WHERE user_id = ?", userId))
        .containsEntry("provider", "KAKAO")
        .containsEntry("provider_subject", PROVIDER_SUBJECT);
    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT account_status, is_completed FROM users WHERE id = ?", userId))
        .containsEntry("account_status", "PENDING")
        .containsEntry("is_completed", false);

    mockMvc
        .perform(get("/api/v1/users/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.userId").value(userId))
        .andExpect(jsonPath("$.data.accountStatus").value("PENDING"))
        .andExpect(jsonPath("$.data.onboardingCompleted").value(false));

    verify(sessionStore)
        .register(any(String.class), eq(userId), eq(DEVICE_ID), any(String.class), any());
  }

  @Test
  void repeatedLoginReusesTheSameOAuthAccount() throws Exception {
    long firstUserId = login().at("/data/user/userId").asLong();
    long secondUserId = login().at("/data/user/userId").asLong();

    assertThat(secondUserId).isEqualTo(firstUserId);
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM users", Integer.class))
        .isEqualTo(1);
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM auth_accounts", Integer.class))
        .isEqualTo(1);
    verify(sessionStore, times(2))
        .register(any(String.class), eq(firstUserId), eq(DEVICE_ID), any(String.class), any());
  }

  @Test
  void repeatedAppleLoginReusesStoredEmailWhenLaterTokenOmitsIt() throws Exception {
    when(providerClient.verify(eq(AuthProvider.APPLE), any()))
        .thenReturn(
            new VerifiedOAuthIdentity(
                AuthProvider.APPLE, "apple-sub", "relay@privaterelay.appleid.com"),
            new VerifiedOAuthIdentity(AuthProvider.APPLE, "apple-sub", null));

    JsonNode firstLogin = appleLogin();
    JsonNode secondLogin = appleLogin();

    assertThat(secondLogin.at("/data/user/userId").asLong())
        .isEqualTo(firstLogin.at("/data/user/userId").asLong());
    assertThat(secondLogin.at("/data/user/email").asText())
        .isEqualTo("relay@privaterelay.appleid.com");
    assertThat(secondLogin.at("/data/user/emailRequired").asBoolean()).isFalse();
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM users", Integer.class))
        .isEqualTo(1);
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM auth_accounts", Integer.class))
        .isEqualTo(1);
  }

  @Test
  void appleLoginAfterWithdrawalCreatesANewUserForTheSameSubject() throws Exception {
    when(providerClient.verify(eq(AuthProvider.APPLE), any()))
        .thenReturn(
            new VerifiedOAuthIdentity(
                AuthProvider.APPLE, "apple-sub", "relay@privaterelay.appleid.com"),
            new VerifiedOAuthIdentity(AuthProvider.APPLE, "apple-sub", null));
    JsonNode firstLogin = appleLogin();
    long withdrawnUserId = firstLogin.at("/data/user/userId").asLong();

    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .header(
                    HttpHeaders.AUTHORIZATION,
                    "Bearer " + firstLogin.at("/data/accessToken").asText())
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNoContent());

    JsonNode rejoined = appleLogin();

    assertThat(rejoined.at("/data/user/userId").asLong()).isNotEqualTo(withdrawnUserId);
    assertThat(rejoined.at("/data/user/emailRequired").asBoolean()).isTrue();
    // 탈퇴는 소프트 삭제다(728) — 옛 사용자 행이 DELETED 로 남고 재가입이 새 행을 만든다.
    // 종전의 COUNT(*)==1 단언은 물리 삭제 전제였다 — 768 에서 새 계약으로 정정.
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM users", Integer.class))
        .isEqualTo(2);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM users WHERE account_status = 'DELETED'", Integer.class))
        .isEqualTo(1);
    // 인증 계정은 탈퇴 시 물리 삭제된다(768) — 남는 것은 재가입이 만든 새 연결 하나뿐이다.
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM auth_accounts", Integer.class))
        .isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject("SELECT provider_subject FROM auth_accounts", String.class))
        .isEqualTo("apple-sub");
    // 그 연결은 새 사용자를 가리켜야 한다 — 옛 행을 재사용했다면 여기서 걸린다.
    assertThat(jdbcTemplate.queryForObject("SELECT user_id FROM auth_accounts", Long.class))
        .isEqualTo(rejoined.at("/data/user/userId").asLong());
  }

  @Test
  void sameVerifiedEmailAcrossProvidersDoesNotMergeAccounts() throws Exception {
    when(providerClient.verify(eq(AuthProvider.APPLE), any()))
        .thenReturn(new VerifiedOAuthIdentity(AuthProvider.APPLE, "apple-sub", "same@example.com"));
    when(providerClient.verify(eq(AuthProvider.GOOGLE), any()))
        .thenReturn(
            new VerifiedOAuthIdentity(AuthProvider.GOOGLE, "google-sub", "same@example.com"));

    long appleUserId = appleLogin().at("/data/user/userId").asLong();
    long googleUserId = googleLogin().at("/data/user/userId").asLong();

    assertThat(googleUserId).isNotEqualTo(appleUserId);
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM users", Integer.class))
        .isEqualTo(2);
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM auth_accounts", Integer.class))
        .isEqualTo(2);
  }

  @Test
  void refreshTokenRotatesOnceAndRejectsReuse() throws Exception {
    JsonNode loginResponse = login();
    long userId = loginResponse.at("/data/user/userId").asLong();
    String refreshToken = loginResponse.at("/data/refreshToken").asText();
    when(sessionStore.rotate(
            any(String.class),
            any(Long.class),
            eq(DEVICE_ID),
            any(String.class),
            any(String.class),
            any()))
        .thenReturn(RefreshTokenRotationResult.ROTATED, RefreshTokenRotationResult.REUSED);

    mockMvc
        .perform(
            post("/api/v1/auth/reissue")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    objectMapper.writeValueAsString(
                        Map.of("refreshToken", refreshToken, "deviceId", DEVICE_ID))))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.accessToken").isNotEmpty())
        .andExpect(jsonPath("$.data.refreshToken").isNotEmpty());

    mockMvc
        .perform(
            post("/api/v1/auth/reissue")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    objectMapper.writeValueAsString(
                        Map.of("refreshToken", refreshToken, "deviceId", DEVICE_ID))))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_004"));

    ArgumentCaptor<String> familyIds = ArgumentCaptor.forClass(String.class);
    ArgumentCaptor<String> currentTokenHashes = ArgumentCaptor.forClass(String.class);
    ArgumentCaptor<String> newTokenHashes = ArgumentCaptor.forClass(String.class);
    verify(sessionStore, times(2))
        .rotate(
            familyIds.capture(),
            eq(userId),
            eq(DEVICE_ID),
            currentTokenHashes.capture(),
            newTokenHashes.capture(),
            any());
    assertThat(familyIds.getAllValues()).allMatch(familyId -> !familyId.isBlank());
    assertThat(familyIds.getAllValues()).containsOnly(familyIds.getAllValues().get(0));
    assertThat(currentTokenHashes.getAllValues())
        .containsOnly(new RefreshTokenHasher().hash(refreshToken));
    assertThat(newTokenHashes.getAllValues()).allMatch(hash -> hash.length() == 64);
    assertThat(newTokenHashes.getAllValues())
        .allSatisfy(
            newHash -> assertThat(newHash).isNotEqualTo(currentTokenHashes.getAllValues().get(0)));
  }

  @Test
  void logoutRevokesOnlyTheCurrentDeviceSession() throws Exception {
    JsonNode loginResponse = login();
    long userId = loginResponse.at("/data/user/userId").asLong();
    String accessToken = loginResponse.at("/data/accessToken").asText();
    String refreshToken = loginResponse.at("/data/refreshToken").asText();
    when(sessionStore.revoke(any(String.class), eq(userId), eq(DEVICE_ID), any(String.class)))
        .thenReturn(true);

    mockMvc
        .perform(
            post("/api/v1/auth/logout")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    objectMapper.writeValueAsString(
                        Map.of("refreshToken", refreshToken, "deviceId", DEVICE_ID))))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"));

    ArgumentCaptor<String> tokenHashes = ArgumentCaptor.forClass(String.class);
    verify(sessionStore)
        .revoke(any(String.class), eq(userId), eq(DEVICE_ID), tokenHashes.capture());
    assertThat(tokenHashes.getValue()).isEqualTo(new RefreshTokenHasher().hash(refreshToken));
    // 로그아웃은 세션만 폐기하며 사용자·인증 계정 행은 유지한다.
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM users", Integer.class))
        .isEqualTo(1);
    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM auth_accounts", Integer.class))
        .isEqualTo(1);
  }

  @Test
  void logoutRejectsUnknownSessionAndRequiresAuthentication() throws Exception {
    JsonNode loginResponse = login();
    long userId = loginResponse.at("/data/user/userId").asLong();
    String accessToken = loginResponse.at("/data/accessToken").asText();
    String refreshToken = loginResponse.at("/data/refreshToken").asText();
    when(sessionStore.revoke(any(String.class), eq(userId), eq(DEVICE_ID), any(String.class)))
        .thenReturn(false);

    mockMvc
        .perform(
            post("/api/v1/auth/logout")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    objectMapper.writeValueAsString(
                        Map.of("refreshToken", refreshToken, "deviceId", DEVICE_ID))))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_003"));

    mockMvc
        .perform(
            post("/api/v1/auth/logout")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    objectMapper.writeValueAsString(
                        Map.of("refreshToken", refreshToken, "deviceId", DEVICE_ID))))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @Test
  void logoutRejectsMalformedRefreshTokenAndMissingFields() throws Exception {
    String accessToken = login().at("/data/accessToken").asText();

    mockMvc
        .perform(
            post("/api/v1/auth/logout")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    objectMapper.writeValueAsString(
                        Map.of("refreshToken", "not-a-jwt", "deviceId", DEVICE_ID))))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_003"));

    mockMvc
        .perform(
            post("/api/v1/auth/logout")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"deviceId\":\"" + DEVICE_ID + "\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  private JsonNode login() throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/auth/oauth/kakao")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        objectMapper.writeValueAsString(
                            Map.of("accessToken", "provider-token", "deviceId", DEVICE_ID))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.grantType").value("Bearer"))
            .andExpect(jsonPath("$.data.user.emailRequired").value(true))
            .andReturn()
            .getResponse()
            .getContentAsString();
    return objectMapper.readTree(body);
  }

  private JsonNode appleLogin() throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/auth/oauth/apple")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        objectMapper.writeValueAsString(
                            Map.of(
                                "idToken",
                                "apple-id-token",
                                "rawNonce",
                                "apple-raw-nonce",
                                "deviceId",
                                DEVICE_ID))))
            .andExpect(status().isOk())
            .andReturn()
            .getResponse()
            .getContentAsString();
    return objectMapper.readTree(body);
  }

  private JsonNode googleLogin() throws Exception {
    String body =
        mockMvc
            .perform(
                post("/api/v1/auth/oauth/google")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(
                        objectMapper.writeValueAsString(
                            Map.of("idToken", "google-id-token", "deviceId", DEVICE_ID))))
            .andExpect(status().isOk())
            .andReturn()
            .getResponse()
            .getContentAsString();
    return objectMapper.readTree(body);
  }
}
