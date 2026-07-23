package com.ssafy.b209.user.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.service.UserOnboardingService;
import com.ssafy.b209.user.service.UserQueryService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(UserController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class UserControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private CurrentAuthenticatedUserResolver currentUserResolver;
  @MockitoBean private UserOnboardingService onboardingService;
  @MockitoBean private UserQueryService queryService;

  @Test
  void returnsTheAuthenticatedUsersCurrentState() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(queryService.getMe(51L))
        .willReturn(
            new UserResponse(
                51L,
                UserRole.GUARDIAN,
                "튼튼이엄마",
                "guardian@example.com",
                AccountStatus.ACTIVE,
                true));

    mockMvc
        .perform(get("/api/v1/users/me"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.userId").value(51))
        .andExpect(jsonPath("$.data.role").value("GUARDIAN"))
        .andExpect(jsonPath("$.data.onboardingCompleted").value(true));
  }

  @Test
  void completesOnboardingAndReturnsTheUpdatedUser() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(onboardingService.completeOnboarding(eq(51L), any(), any(), any()))
        .willReturn(
            new UserResponse(
                51L,
                UserRole.GUARDIAN,
                "튼튼이엄마",
                "guardian@example.com",
                AccountStatus.ACTIVE,
                true));

    mockMvc
        .perform(
            put("/api/v1/users/me/onboarding")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "role": "GUARDIAN",
                      "nickname": "튼튼이엄마",
                      "email": "guardian@example.com",
                      "consents": [{"termId": 1, "action": "AGREE"}]
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.userId").value(51))
        .andExpect(jsonPath("$.data.role").value("GUARDIAN"))
        .andExpect(jsonPath("$.data.email").value("guardian@example.com"))
        .andExpect(jsonPath("$.data.accountStatus").value("ACTIVE"))
        .andExpect(jsonPath("$.data.onboardingCompleted").value(true));
  }

  @Test
  void rejectsAnOnboardingRequestMissingRequiredFields() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);

    mockMvc
        .perform(
            put("/api/v1/users/me/onboarding")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "nickname": "튼튼이엄마",
                      "consents": [{"termId": 1, "action": "AGREE"}]
                    }
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void returnsUnauthorizedWhenAccessTokenIsMissing() throws Exception {
    given(currentUserResolver.requireUserId())
        .willThrow(new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED));

    mockMvc
        .perform(
            put("/api/v1/users/me/onboarding")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "role": "GUARDIAN",
                      "nickname": "튼튼이엄마",
                      "email": "guardian@example.com",
                      "consents": [{"termId": 1, "action": "AGREE"}]
                    }
                    """))
        .andExpect(status().isUnauthorized());
  }
}
