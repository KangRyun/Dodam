package com.ssafy.b209.auth.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;
import com.ssafy.b209.auth.service.OAuthLoginResult;
import com.ssafy.b209.auth.service.OAuthLoginService;
import com.ssafy.b209.auth.service.OAuthLoginUser;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(OAuthController.class)
class OAuthControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private OAuthLoginService loginService;

  @Test
  void logsInWithKakaoAccessTokenAndCommonResponseEnvelope() throws Exception {
    when(loginService.login(eq(AuthProvider.KAKAO), any(OAuthLoginRequest.class)))
        .thenReturn(
            new OAuthLoginResult(
                "Bearer",
                "access-token",
                1800,
                "refresh-token",
                1209600,
                new OAuthLoginUser(41L, null, null, null, true, AccountStatus.PENDING, false)));

    mockMvc
        .perform(
            post("/api/v1/auth/oauth/kakao")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "accessToken": "kakao-access-token",
                      "deviceId": "device-1"
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.data.grantType").value("Bearer"))
        .andExpect(jsonPath("$.data.accessToken").value("access-token"))
        .andExpect(jsonPath("$.data.refreshToken").value("refresh-token"))
        .andExpect(jsonPath("$.data.user.userId").value(41))
        .andExpect(jsonPath("$.data.user.accountStatus").value("PENDING"))
        .andExpect(jsonPath("$.data.user.onboardingCompleted").value(false));

    verify(loginService)
        .login(
            eq(AuthProvider.KAKAO),
            argThat(
                request ->
                    "kakao-access-token".equals(request.accessToken())
                        && request.idToken() == null));
  }

  @Test
  void logsInWithGoogleIdToken() throws Exception {
    when(loginService.login(eq(AuthProvider.GOOGLE), any(OAuthLoginRequest.class)))
        .thenReturn(
            new OAuthLoginResult(
                "Bearer",
                "access-token",
                1800,
                "refresh-token",
                1209600,
                new OAuthLoginUser(
                    42L, null, null, "guardian@example.com", false, AccountStatus.ACTIVE, true)));

    mockMvc
        .perform(
            post("/api/v1/auth/oauth/google")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "idToken": "google-id-token",
                      "deviceId": "device-1"
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.data.user.userId").value(42));

    verify(loginService)
        .login(
            eq(AuthProvider.GOOGLE),
            argThat(
                request ->
                    request.accessToken() == null && "google-id-token".equals(request.idToken())));
  }

  @Test
  void rejectsUnsupportedProviderWithoutCallingExternalSystem() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/auth/oauth/local")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "accessToken": "provider-token",
                      "deviceId": "device-1"
                    }
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.success").value(false))
        .andExpect(jsonPath("$.code").value("AUTH_400_001"));
  }

  @Test
  void validatesRequiredProviderTokenAndDeviceId() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/auth/oauth/google").contentType(MediaType.APPLICATION_JSON).content("{}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.success").value(false));
  }
}
