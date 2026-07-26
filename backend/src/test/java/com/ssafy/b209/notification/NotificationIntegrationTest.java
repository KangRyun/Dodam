package com.ssafy.b209.notification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.notification.service.DeviceTokenCipher;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 알림 4개 endpoint(NOTI-01~04)를 실 MySQL로 관통 검증한다.
 *
 * <p>V14가 추가한 {@code device_id} UNIQUE 제약이 실제로 upsert를 성립시키는지, Token이 평문으로 저장되지 않는지, 목록이 정규화된 부가
 * 속성과 관련 자원을 조립하는지를 DB 상태까지 확인한다. 인증은 다른 단면 통합 테스트와 같이 검증된 {@link AuthenticatedUser} Principal을
 * SecurityContext에 넣어 재현한다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
@TestPropertySource(
    properties =
        "app.push.device-token.encryption-key=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=")
class NotificationIntegrationTest {

  private static final Long USER_ID = 41L;
  private static final Long OTHER_USER_ID = 42L;
  private static final String DEVICE_ID = "installation-uuid";

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_notification")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private DeviceTokenCipher cipher;

  @BeforeEach
  void setUp() {
    authenticate(USER_ID);
    jdbcTemplate.update("DELETE FROM notification_attributes");
    jdbcTemplate.update("DELETE FROM notifications");
    jdbcTemplate.update("DELETE FROM notification_device_tokens");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) VALUES "
            + "(?, 'GUARDIAN', 'noti-guardian', 'ACTIVE'), "
            + "(?, 'GUARDIAN', 'other-guardian', 'ACTIVE')",
        USER_ID,
        OTHER_USER_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  // ---------------------------------------------------------------- NOTI-01 등록·갱신

  @Test
  void storesDeviceTokenSealedAndHashedWithoutPlaintext() throws Exception {
    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "ANDROID", "fcm-token-1", "1.0.0"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.registered").value(true))
        .andExpect(jsonPath("$.data.pushProvider").value("FCM"));

    Map<String, Object> stored =
        jdbcTemplate.queryForMap(
            "SELECT token_ciphertext, token_hash, platform, push_provider, app_version, is_active "
                + "FROM notification_device_tokens WHERE user_id = ? AND device_id = ?",
            USER_ID,
            DEVICE_ID);
    assertThat((String) stored.get("token_ciphertext")).doesNotContain("fcm-token-1");
    assertThat(cipher.decrypt((String) stored.get("token_ciphertext"))).isEqualTo("fcm-token-1");
    assertThat((String) stored.get("token_hash")).hasSize(64);
    assertThat(stored.get("platform")).isEqualTo("ANDROID");
    assertThat(stored.get("push_provider")).isEqualTo("FCM");
    assertThat(stored.get("app_version")).isEqualTo("1.0.0");
    assertThat(stored.get("is_active")).isEqualTo(true);
  }

  @Test
  void upsertsTheSameDeviceInsteadOfAccumulatingRows() throws Exception {
    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "ANDROID", "fcm-token-1", "1.0.0"))
        .andExpect(status().isOk());
    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "IOS", "fcm-token-2", "1.1.0"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.registered").value(false))
        .andExpect(jsonPath("$.data.platform").value("IOS"));

    // V14의 (user_id, device_id) UNIQUE가 없으면 갱신이 아니라 행이 쌓인다.
    assertThat(deviceTokenCount()).isEqualTo(1);
    Map<String, Object> stored =
        jdbcTemplate.queryForMap(
            "SELECT token_ciphertext, platform, app_version FROM notification_device_tokens "
                + "WHERE user_id = ? AND device_id = ?",
            USER_ID,
            DEVICE_ID);
    assertThat(cipher.decrypt((String) stored.get("token_ciphertext"))).isEqualTo("fcm-token-2");
    assertThat(stored.get("platform")).isEqualTo("IOS");
    assertThat(stored.get("app_version")).isEqualTo("1.1.0");
  }

  @Test
  void rejectsTokenAlreadyRegisteredToAnotherAccount() throws Exception {
    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "ANDROID", "shared-token", "1.0.0"))
        .andExpect(status().isOk());

    authenticate(OTHER_USER_ID);
    mockMvc
        .perform(registerDeviceToken("another-device", "ANDROID", "shared-token", "1.0.0"))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("DEVICE_TOKEN_ALREADY_REGISTERED"));

    assertThat(deviceTokenCount()).isEqualTo(1);
  }

  @Test
  void rejectsUnknownPlatformAndMissingBodyWithTheSameCode() throws Exception {
    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "PC", "fcm-token", "1.0.0"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("DEVICE_TOKEN_INVALID"));

    mockMvc
        .perform(post("/api/v1/notifications/device-tokens"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("DEVICE_TOKEN_INVALID"));

    assertThat(deviceTokenCount()).isZero();
  }

  // ---------------------------------------------------------------- NOTI-02 해제

  @Test
  void deactivatesDeviceTokenAndKeepsTheRowForAudit() throws Exception {
    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "ANDROID", "fcm-token-1", "1.0.0"))
        .andExpect(status().isOk());

    mockMvc
        .perform(delete("/api/v1/notifications/device-tokens/{deviceId}", DEVICE_ID))
        .andExpect(status().isNoContent());

    assertThat(deviceTokenCount()).isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT is_active FROM notification_device_tokens "
                    + "WHERE user_id = ? AND device_id = ?",
                Boolean.class,
                USER_ID,
                DEVICE_ID))
        .isFalse();
  }

  @Test
  void reactivatesDeviceTokenWhenTheSameDeviceRegistersAgain() throws Exception {
    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "ANDROID", "fcm-token-1", "1.0.0"))
        .andExpect(status().isOk());
    mockMvc
        .perform(delete("/api/v1/notifications/device-tokens/{deviceId}", DEVICE_ID))
        .andExpect(status().isNoContent());

    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "ANDROID", "fcm-token-3", "1.0.0"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.active").value(true));

    assertThat(deviceTokenCount()).isEqualTo(1);
  }

  @Test
  void hidesOtherUsersDeviceOnRelease() throws Exception {
    mockMvc
        .perform(registerDeviceToken(DEVICE_ID, "ANDROID", "fcm-token-1", "1.0.0"))
        .andExpect(status().isOk());

    authenticate(OTHER_USER_ID);
    mockMvc
        .perform(delete("/api/v1/notifications/device-tokens/{deviceId}", DEVICE_ID))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DEVICE_TOKEN_NOT_FOUND"));
  }

  // ---------------------------------------------------------------- NOTI-03 목록

  @Test
  void listsOnlyOwnNotificationsLatestFirstWithNormalizedData() throws Exception {
    insertNotification(900L, USER_ID, "ANALYSIS_COMPLETED", "SENT", null, "2026-07-26 10:00:00");
    insertNotification(901L, USER_ID, "RETENTION_NOTICE", "SENT", null, "2026-07-26 11:00:00");
    insertNotification(
        902L, OTHER_USER_ID, "ANALYSIS_COMPLETED", "SENT", null, "2026-07-26 12:00:00");
    jdbcTemplate.update(
        "INSERT INTO notification_attributes "
            + "(notification_id, attribute_key, value_type, value_text) "
            + "VALUES (900, 'analysisId', 'NUMBER', '77')");

    mockMvc
        .perform(get("/api/v1/notifications"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(2))
        .andExpect(jsonPath("$.data.content[0].notificationId").value(901))
        .andExpect(jsonPath("$.data.content[1].notificationId").value(900))
        .andExpect(jsonPath("$.data.content[1].data.analysisId").value("77"))
        .andExpect(jsonPath("$.data.content[0].data").isEmpty());
  }

  @Test
  void filtersByTypeAndUnreadOnly() throws Exception {
    insertNotification(
        900L, USER_ID, "ANALYSIS_COMPLETED", "SENT", "2026-07-26 10:30:00", "2026-07-26 10:00:00");
    insertNotification(901L, USER_ID, "ANALYSIS_COMPLETED", "SENT", null, "2026-07-26 11:00:00");
    insertNotification(902L, USER_ID, "RETENTION_NOTICE", "SENT", null, "2026-07-26 12:00:00");

    mockMvc
        .perform(get("/api/v1/notifications").queryParam("type", "ANALYSIS_COMPLETED"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(2));

    mockMvc
        .perform(get("/api/v1/notifications").queryParam("unreadOnly", "true"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(2));

    mockMvc
        .perform(
            get("/api/v1/notifications")
                .queryParam("type", "ANALYSIS_COMPLETED")
                .queryParam("unreadOnly", "true"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(jsonPath("$.data.content[0].notificationId").value(901));
  }

  @Test
  void returnsEmptyPageInsteadOfNotFound() throws Exception {
    mockMvc
        .perform(get("/api/v1/notifications"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content").isEmpty())
        .andExpect(jsonPath("$.data.totalElements").value(0))
        .andExpect(jsonPath("$.data.hasNext").value(false));
  }

  @Test
  void rejectsTypeOutsideTheDatabaseVocabulary() throws Exception {
    mockMvc
        .perform(get("/api/v1/notifications").queryParam("type", "UNKNOWN_TYPE"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  // ---------------------------------------------------------------- NOTI-04 단건 읽음

  @Test
  void marksNotificationReadIdempotently() throws Exception {
    insertNotification(900L, USER_ID, "ANALYSIS_COMPLETED", "SENT", null, "2026-07-26 10:00:00");

    String firstReadAt =
        mockMvc
            .perform(patch("/api/v1/notifications/{notificationId}/read", 900L))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.notificationId").value(900))
            .andExpect(jsonPath("$.data.readAt").exists())
            .andReturn()
            .getResponse()
            .getContentAsString();

    mockMvc
        .perform(patch("/api/v1/notifications/{notificationId}/read", 900L))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.notificationId").value(900));

    assertThat(firstReadAt).contains("readAt");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM notifications WHERE id = 900 AND read_at IS NOT NULL",
                Integer.class))
        .isEqualTo(1);
  }

  @Test
  void hidesOtherUsersNotificationOnRead() throws Exception {
    insertNotification(
        902L, OTHER_USER_ID, "ANALYSIS_COMPLETED", "SENT", null, "2026-07-26 10:00:00");

    mockMvc
        .perform(patch("/api/v1/notifications/{notificationId}/read", 902L))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("NOTIFICATION_NOT_FOUND"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM notifications WHERE id = 902 AND read_at IS NULL",
                Integer.class))
        .isEqualTo(1);
  }

  // ---------------------------------------------------------------- helpers

  private org.springframework.test.web.servlet.RequestBuilder registerDeviceToken(
      String deviceId, String platform, String pushToken, String appVersion) {
    return post("/api/v1/notifications/device-tokens")
        .contentType(MediaType.APPLICATION_JSON)
        .content(
            """
            {
              "deviceId": "%s",
              "platform": "%s",
              "pushToken": "%s",
              "appVersion": "%s"
            }
            """
                .formatted(deviceId, platform, pushToken, appVersion));
  }

  private void insertNotification(
      Long id,
      Long recipientUserId,
      String type,
      String deliveryStatus,
      String readAt,
      String createdAt) {
    jdbcTemplate.update(
        "INSERT INTO notifications "
            + "(id, recipient_user_id, notification_type, title, content, delivery_status, "
            + "read_at, sent_at, created_at) "
            + "VALUES (?, ?, ?, '분석이 완료됐어요', '리포트를 확인해 보세요', ?, ?, ?, ?)",
        id,
        recipientUserId,
        type,
        deliveryStatus,
        readAt,
        createdAt,
        createdAt);
  }

  private int deviceTokenCount() {
    return jdbcTemplate.queryForObject(
        "SELECT COUNT(*) FROM notification_device_tokens", Integer.class);
  }

  private void authenticate(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
