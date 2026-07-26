package com.ssafy.b209.notification.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.dto.response.DeviceTokenResponse;
import com.ssafy.b209.notification.dto.response.NotificationListItemResponse;
import com.ssafy.b209.notification.dto.response.NotificationListPageResponse;
import com.ssafy.b209.notification.dto.response.NotificationReadResponse;
import com.ssafy.b209.notification.exception.NotificationErrorCode;
import com.ssafy.b209.notification.service.DeviceTokenService;
import com.ssafy.b209.notification.service.NotificationQueryService;
import com.ssafy.b209.notification.service.NotificationReadService;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/** 알림 4개 endpoint의 HTTP 계약(응답 형태·오류 코드·Token 비노출)을 검증한다. */
@WebMvcTest({NotificationDeviceTokenController.class, NotificationInboxController.class})
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class NotificationControllerTest {

  private static final Long USER_ID = 41L;

  @Autowired private MockMvc mockMvc;

  @MockitoBean private CurrentAuthenticatedUserResolver currentUserResolver;
  @MockitoBean private DeviceTokenService deviceTokenService;
  @MockitoBean private NotificationQueryService notificationQueryService;
  @MockitoBean private NotificationReadService notificationReadService;

  @Test
  void registersDeviceTokenWithoutEchoingTheTokenValue() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);
    given(deviceTokenService.register(eq(USER_ID), any()))
        .willReturn(
            new DeviceTokenResponse(
                "installation-uuid",
                "ANDROID",
                "FCM",
                true,
                true,
                LocalDateTime.parse("2026-07-26T12:00:00")));

    mockMvc
        .perform(
            post("/api/v1/notifications/device-tokens")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    "{\"deviceId\":\"installation-uuid\",\"platform\":\"ANDROID\","
                        + "\"pushToken\":\"fcm-token\",\"appVersion\":\"1.0.0\"}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.deviceId").value("installation-uuid"))
        .andExpect(jsonPath("$.data.pushProvider").value("FCM"))
        .andExpect(jsonPath("$.data.registered").value(true))
        .andExpect(jsonPath("$.data.active").value(true))
        // Token 원문·암호문·hash는 응답에 실리지 않는다.
        .andExpect(jsonPath("$.data.pushToken").doesNotExist())
        .andExpect(jsonPath("$.data.tokenHash").doesNotExist());
  }

  @Test
  void reportsInvalidDeviceTokenRequestWithSpecCode() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);
    willThrow(new BusinessException(NotificationErrorCode.DEVICE_TOKEN_INVALID))
        .given(deviceTokenService)
        .register(eq(USER_ID), any());

    mockMvc
        .perform(
            post("/api/v1/notifications/device-tokens")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"deviceId\":\"\",\"platform\":\"ANDROID\",\"pushToken\":\"t\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("DEVICE_TOKEN_INVALID"));
  }

  @Test
  void reportsMissingEncryptionKeyAsServiceUnavailable() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);
    willThrow(new BusinessException(NotificationErrorCode.DEVICE_TOKEN_STORAGE_UNAVAILABLE))
        .given(deviceTokenService)
        .register(eq(USER_ID), any());

    mockMvc
        .perform(
            post("/api/v1/notifications/device-tokens")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"deviceId\":\"d\",\"platform\":\"ANDROID\",\"pushToken\":\"t\"}"))
        .andExpect(status().isServiceUnavailable())
        .andExpect(jsonPath("$.code").value("DEVICE_TOKEN_STORAGE_UNAVAILABLE"));
  }

  @Test
  void releasesDeviceTokenWithNoContent() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);

    mockMvc
        .perform(delete("/api/v1/notifications/device-tokens/{deviceId}", "installation-uuid"))
        .andExpect(status().isNoContent());

    verify(deviceTokenService).release(USER_ID, "installation-uuid");
  }

  @Test
  void reportsMissingDeviceOnRelease() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);
    willThrow(new BusinessException(NotificationErrorCode.DEVICE_TOKEN_NOT_FOUND))
        .given(deviceTokenService)
        .release(USER_ID, "unknown-device");

    mockMvc
        .perform(delete("/api/v1/notifications/device-tokens/{deviceId}", "unknown-device"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DEVICE_TOKEN_NOT_FOUND"));
  }

  @Test
  void appliesSpecDefaultQueryValuesForTheInbox() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);
    given(notificationQueryService.getNotifications(USER_ID, null, false, 0, 20))
        .willReturn(page(List.of()));

    mockMvc.perform(get("/api/v1/notifications")).andExpect(status().isOk());

    // 명세 15.3 기본값: unreadOnly=false, page=0, size=20.
    verify(notificationQueryService).getNotifications(USER_ID, null, false, 0, 20);
  }

  @Test
  void returnsInboxItemsWithRelatedResourceAndData() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);
    given(notificationQueryService.getNotifications(USER_ID, "ANALYSIS_COMPLETED", true, 1, 10))
        .willReturn(
            page(
                List.of(
                    new NotificationListItemResponse(
                        900L,
                        "ANALYSIS_COMPLETED",
                        "분석이 완료됐어요",
                        "리포트를 확인해 보세요",
                        "REPORT",
                        55L,
                        Map.of("analysisId", "77"),
                        "SENT",
                        null,
                        LocalDateTime.parse("2026-07-26T11:00:00"),
                        LocalDateTime.parse("2026-07-26T10:00:00")))));

    mockMvc
        .perform(
            get("/api/v1/notifications")
                .queryParam("type", "ANALYSIS_COMPLETED")
                .queryParam("unreadOnly", "true")
                .queryParam("page", "1")
                .queryParam("size", "10"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content[0].notificationId").value(900))
        .andExpect(jsonPath("$.data.content[0].relatedResourceType").value("REPORT"))
        .andExpect(jsonPath("$.data.content[0].relatedResourceId").value(55))
        .andExpect(jsonPath("$.data.content[0].data.analysisId").value("77"))
        .andExpect(jsonPath("$.data.content[0].readAt").doesNotExist())
        // 서버가 이동 URL을 만들지 않는다.
        .andExpect(jsonPath("$.data.content[0].linkUrl").doesNotExist());
  }

  @Test
  void marksNotificationReadAndReturnsFirstReadTime() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);
    given(notificationReadService.markRead(USER_ID, 900L))
        .willReturn(new NotificationReadResponse(900L, LocalDateTime.parse("2026-07-26T12:00:00")));

    mockMvc
        .perform(patch("/api/v1/notifications/{notificationId}/read", 900L))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.notificationId").value(900))
        .andExpect(jsonPath("$.data.readAt").value("2026-07-26T12:00:00"));
  }

  @Test
  void hidesOtherUsersNotificationBehindNotFound() throws Exception {
    given(currentUserResolver.requireUserId()).willReturn(USER_ID);
    willThrow(new BusinessException(NotificationErrorCode.NOTIFICATION_NOT_FOUND))
        .given(notificationReadService)
        .markRead(USER_ID, 999L);

    mockMvc
        .perform(patch("/api/v1/notifications/{notificationId}/read", 999L))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("NOTIFICATION_NOT_FOUND"));
  }

  private NotificationListPageResponse page(List<NotificationListItemResponse> content) {
    return new NotificationListPageResponse(
        content, 0, 20, content.size(), content.isEmpty() ? 0 : 1, true, true, false);
  }
}
