package com.ssafy.b209.user.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.response.DataRetentionPolicyResponse;
import com.ssafy.b209.user.dto.response.NotificationSettingsResponse;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.service.UserDataRetentionPolicyReader;
import com.ssafy.b209.user.service.UserDeletionService;
import com.ssafy.b209.user.service.UserNotificationSettingsReader;
import com.ssafy.b209.user.service.UserNotificationSettingsUpdateService;
import com.ssafy.b209.user.service.UserOnboardingService;
import com.ssafy.b209.user.service.UserQueryService;
import com.ssafy.b209.user.service.UserUpdateService;
import java.time.Instant;
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
  @MockitoBean private UserUpdateService updateService;
  @MockitoBean private UserDeletionService deletionService;
  @MockitoBean private UserNotificationSettingsReader notificationSettingsReader;
  @MockitoBean private UserNotificationSettingsUpdateService notificationSettingsUpdateService;
  @MockitoBean private UserDataRetentionPolicyReader dataRetentionPolicyReader;

  @Test
  void immediatelyDeletesTheAuthenticatedUserAfterExplicitConfirmation() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);

    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNoContent());

    verify(deletionService)
        .delete(
            eq(51L),
            org.mockito.ArgumentMatchers.argThat(
                request -> "DELETE".equals(request.confirmation())));
  }

  @Test
  void updatesTheAuthenticatedUsersNickname() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(updateService.updateProfile(eq(51L), any())).willReturn(userResponse("새별이"));

    mockMvc
        .perform(
            patch("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"nickname\": \"새별이\"}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.nickname").value("새별이"));
  }

  @Test
  void returnsTheAuthenticatedUsersCurrentState() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(queryService.getMe(51L)).willReturn(userResponse("튼튼이엄마"));

    mockMvc
        .perform(get("/api/v1/users/me"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.userId").value(51))
        .andExpect(jsonPath("$.data.role").value("GUARDIAN"))
        .andExpect(jsonPath("$.data.onboardingCompleted").value(true));
  }

  @Test
  void returnsTheAuthenticatedUsersNotificationSettings() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(notificationSettingsReader.read(51L))
        .willReturn(new NotificationSettingsResponse(false, true, false, true));

    mockMvc
        .perform(get("/api/v1/users/me/notification-settings"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.analysisCompleted").value(false))
        .andExpect(jsonPath("$.data.community").value(true))
        .andExpect(jsonPath("$.data.serviceNotice").value(false))
        .andExpect(jsonPath("$.data.marketing").value(true));
  }

  @Test
  void returnsDefaultNotificationSettingsWhenNoRowExists() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(notificationSettingsReader.read(51L)).willReturn(NotificationSettingsResponse.defaults());

    mockMvc
        .perform(get("/api/v1/users/me/notification-settings"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.analysisCompleted").value(true))
        .andExpect(jsonPath("$.data.community").value(true))
        .andExpect(jsonPath("$.data.serviceNotice").value(true))
        .andExpect(jsonPath("$.data.marketing").value(false));
  }

  @Test
  void returnsUnauthorizedForNotificationSettingsWhenAccessTokenIsMissing() throws Exception {
    given(currentUserResolver.requireUserId())
        .willThrow(new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED));

    mockMvc
        .perform(get("/api/v1/users/me/notification-settings"))
        .andExpect(status().isUnauthorized());
  }

  @Test
  void updatesTheAuthenticatedUsersNotificationSettings() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(notificationSettingsUpdateService.update(eq(51L), any()))
        .willReturn(new NotificationSettingsResponse(false, true, false, true));

    mockMvc
        .perform(
            patch("/api/v1/users/me/notification-settings")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "analysisCompleted": false,
                      "community": true,
                      "serviceNotice": false,
                      "marketing": true
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.analysisCompleted").value(false))
        .andExpect(jsonPath("$.data.community").value(true))
        .andExpect(jsonPath("$.data.serviceNotice").value(false))
        .andExpect(jsonPath("$.data.marketing").value(true));

    verify(notificationSettingsUpdateService)
        .update(
            eq(51L),
            org.mockito.ArgumentMatchers.argThat(
                request ->
                    Boolean.FALSE.equals(request.analysisCompleted())
                        && Boolean.TRUE.equals(request.community())
                        && Boolean.FALSE.equals(request.serviceNotice())
                        && Boolean.TRUE.equals(request.marketing())));
  }

  @Test
  void rejectsNotificationSettingsUpdateMissingRequiredField() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);

    mockMvc
        .perform(
            patch("/api/v1/users/me/notification-settings")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "analysisCompleted": true,
                      "community": true,
                      "serviceNotice": true
                    }
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    verify(notificationSettingsUpdateService, never()).update(any(), any());
  }

  @Test
  void returnsUnauthorizedForNotificationSettingsUpdateWhenAccessTokenIsMissing() throws Exception {
    given(currentUserResolver.requireUserId())
        .willThrow(new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED));

    mockMvc
        .perform(
            patch("/api/v1/users/me/notification-settings")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "analysisCompleted": true,
                      "community": true,
                      "serviceNotice": true,
                      "marketing": false
                    }
                    """))
        .andExpect(status().isUnauthorized());
  }

  @Test
  void returnsTheAuthenticatedUsersDataRetentionPolicy() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(dataRetentionPolicyReader.read(51L))
        .willReturn(DataRetentionPolicyResponse.provisional(365, 14));

    mockMvc
        .perform(get("/api/v1/users/me/data-retention"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.retentionDays").value(365))
        .andExpect(jsonPath("$.data.noticeDaysBefore").value(14))
        .andExpect(jsonPath("$.data.policyStatus").value("PROVISIONAL"));
  }

  @Test
  void returnsDefaultDataRetentionPolicyWhenNoRowExists() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(dataRetentionPolicyReader.read(51L)).willReturn(DataRetentionPolicyResponse.defaults());

    mockMvc
        .perform(get("/api/v1/users/me/data-retention"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.retentionDays").value(180))
        .andExpect(jsonPath("$.data.noticeDaysBefore").value(30))
        .andExpect(jsonPath("$.data.policyStatus").value("PROVISIONAL"));
  }

  @Test
  void returnsUnauthorizedForDataRetentionPolicyWhenAccessTokenIsMissing() throws Exception {
    given(currentUserResolver.requireUserId())
        .willThrow(new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED));

    mockMvc.perform(get("/api/v1/users/me/data-retention")).andExpect(status().isUnauthorized());

    verify(dataRetentionPolicyReader, never()).read(any());
  }

  @Test
  void completesOnboardingAndReturnsTheUpdatedUser() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(51L);
    given(onboardingService.completeOnboarding(eq(51L), any(), any(), any()))
        .willReturn(userResponse("튼튼이엄마"));

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

  private static UserResponse userResponse(String nickname) {
    return new UserResponse(
        51L,
        UserRole.GUARDIAN,
        nickname,
        "guardian@example.com",
        AccountStatus.ACTIVE,
        "https://cdn.example.com/profile/51.png",
        NotificationSettingsResponse.defaults(),
        true,
        Instant.parse("2026-07-24T12:00:00Z"),
        Instant.parse("2026-07-20T01:00:00Z"));
  }
}
