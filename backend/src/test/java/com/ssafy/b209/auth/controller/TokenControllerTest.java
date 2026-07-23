package com.ssafy.b209.auth.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.dto.request.TokenReissueRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.service.OAuthLoginResult;
import com.ssafy.b209.auth.service.OAuthLoginUser;
import com.ssafy.b209.auth.service.RefreshTokenService;
import com.ssafy.b209.global.exception.BusinessException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(TokenController.class)
class TokenControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private RefreshTokenService refreshTokenService;

  @Test
  void reissuesTokenPairWithCommonResponseEnvelope() throws Exception {
    when(refreshTokenService.reissue(any(TokenReissueRequest.class)))
        .thenReturn(
            new OAuthLoginResult(
                "Bearer",
                "new-access",
                1800,
                "new-refresh",
                1209600,
                new OAuthLoginUser(41L, null, null, null, true, AccountStatus.PENDING, false)));

    mockMvc
        .perform(
            post("/api/v1/auth/reissue")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {"refreshToken":"old-refresh","deviceId":"device-1"}
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.data.accessToken").value("new-access"))
        .andExpect(jsonPath("$.data.refreshToken").value("new-refresh"));
  }

  @Test
  void returnsSafeErrorWhenRefreshTokenWasReused() throws Exception {
    when(refreshTokenService.reissue(any(TokenReissueRequest.class)))
        .thenThrow(new BusinessException(AuthErrorCode.REFRESH_TOKEN_REUSED));

    mockMvc
        .perform(
            post("/api/v1/auth/reissue")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {"refreshToken":"reused-refresh","deviceId":"device-1"}
                    """))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.success").value(false))
        .andExpect(jsonPath("$.code").value("AUTH_401_004"));
  }

  @Test
  void validatesRefreshTokenAndDeviceId() throws Exception {
    mockMvc
        .perform(post("/api/v1/auth/reissue").contentType(MediaType.APPLICATION_JSON).content("{}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.success").value(false));
  }
}
