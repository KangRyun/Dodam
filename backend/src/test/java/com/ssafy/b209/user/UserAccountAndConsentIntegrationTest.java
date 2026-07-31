package com.ssafy.b209.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.support.SharedMongoContainer;
import java.util.List;
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
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 회원 본인 정보 3개 endpoint(조회·수정·탈퇴)와 아동 범위 동의 경계를 실 MySQL로 관통 검증하는 통합 테스트다.
 *
 * <p>{@code /users/me}에는 단위 테스트만 있어 명세 6.3 응답 확장과 {@code AccountStatus} Enum↔CHECK 정합을 실 DB에서 확인할
 * 수단이 없었다. 특히 {@code user_notification_settings}는 Entity 없이 Native Query Projection으로만 읽으므로 Spring
 * 기동과 실제 조회 없이는 검증되지 않는다.
 *
 * <p>사용자 범위 동의 현황·선택 동의 변경·이력은 {@code ConsentStatusIntegrationTest}가 이미 덮으므로, 이 클래스는 중복을 피해 아동 범위와
 * 권한·검증 경계만 다룬다. 인증은 다른 단면 통합 테스트와 같이 검증된 {@link AuthenticatedUser} Principal을 SecurityContext에 넣어
 * 재현한다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class UserAccountAndConsentIntegrationTest {

  private static final Long USER_ID = 41L;
  private static final Long OTHER_USER_ID = 42L;
  private static final Long MISSING_USER_ID = 999L;
  private static final Long CHILD_ID = 1L;
  private static final Long OTHER_CHILD_ID = 2L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_user_account")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  /**
   * 탈퇴는 아동의 스트로크를 MongoDB 에서 동반 삭제한다(S15P11B209-365).
   *
   * <p>이 클래스는 {@code IntegrationTestSupport} 를 상속하지 않는 예외라 여기서 직접 붙인다. 없어도 삭제 실패는 삼켜지지만(ERROR 로그),
   * 그러면 가드레일이 실제로 도는지 검증하지 못한 채 초록이 된다.
   */
  @DynamicPropertySource
  static void strokeStoreProperties(DynamicPropertyRegistry registry) {
    SharedMongoContainer.registerTo(registry);
  }

  @BeforeEach
  void setUp() {
    authenticate(USER_ID);
    jdbcTemplate.update("DELETE FROM consent_records");
    jdbcTemplate.update("DELETE FROM consent_terms");
    jdbcTemplate.update("DELETE FROM user_notification_settings");
    jdbcTemplate.update("DELETE FROM user_data_retention_settings");
    jdbcTemplate.update("DELETE FROM auth_accounts");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM child_response_modes");
    jdbcTemplate.update("DELETE FROM children");
    // 전문가 탈퇴 테스트 잔재 정리. activity_templates → expert_profiles → users 순서를 지켜야 한다
    //   (FK 방향의 역순). 어긋나면 RESTRICT 에 걸려 다음 테스트의 setUp 이 통째로 실패한다.
    jdbcTemplate.update("DELETE FROM activity_templates");
    jdbcTemplate.update("DELETE FROM expert_profiles");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users "
            + "(id, role, nickname, email, account_status, profile_image_url, is_completed, "
            + "last_login_at, created_at) VALUES "
            + "(?, 'GUARDIAN', '별이맘', 'guardian@example.com', 'ACTIVE', "
            + "'https://cdn.example.com/me.png', TRUE, "
            + "'2026-07-24 12:00:00.000000', '2026-07-01 03:04:05.000000'), "
            + "(?, 'GUARDIAN', '다른보호자', NULL, 'ACTIVE', NULL, TRUE, NULL, "
            + "'2026-07-02 00:00:00.000000')",
        USER_ID,
        OTHER_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, '별이', '2020-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE'), "
            + "(?, '남의아이', '2019-05-06', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID,
        OTHER_CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, ?, 'MOTHER')",
        USER_ID,
        CHILD_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  // ---------------------------------------------------------------- 312·324 내 정보 조회

  @Test
  void returnsStoredProfileAndNotificationSettings() throws Exception {
    jdbcTemplate.update(
        "INSERT INTO user_notification_settings "
            + "(user_id, analysis_completed, community, service_notice, marketing) "
            + "VALUES (?, TRUE, FALSE, TRUE, TRUE)",
        USER_ID);

    mockMvc
        .perform(get("/api/v1/users/me"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.userId").value(USER_ID))
        .andExpect(jsonPath("$.data.role").value("GUARDIAN"))
        .andExpect(jsonPath("$.data.nickname").value("별이맘"))
        .andExpect(jsonPath("$.data.email").value("guardian@example.com"))
        .andExpect(jsonPath("$.data.accountStatus").value("ACTIVE"))
        .andExpect(jsonPath("$.data.profileImageUrl").value("https://cdn.example.com/me.png"))
        .andExpect(jsonPath("$.data.notificationSettings.analysisCompleted").value(true))
        .andExpect(jsonPath("$.data.notificationSettings.community").value(false))
        .andExpect(jsonPath("$.data.notificationSettings.serviceNotice").value(true))
        .andExpect(jsonPath("$.data.notificationSettings.marketing").value(true))
        .andExpect(jsonPath("$.data.onboardingCompleted").value(true))
        .andExpect(jsonPath("$.data.lastLoginAt").value("2026-07-24T12:00:00Z"))
        .andExpect(jsonPath("$.data.createdAt").value("2026-07-01T03:04:05Z"));
  }

  @Test
  void fallsBackToColumnDefaultsWhenNotificationSettingsRowIsMissing() throws Exception {
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM user_notification_settings WHERE user_id = ?",
                Integer.class,
                USER_ID))
        .isZero();

    mockMvc
        .perform(get("/api/v1/users/me"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.notificationSettings.analysisCompleted").value(true))
        .andExpect(jsonPath("$.data.notificationSettings.community").value(true))
        .andExpect(jsonPath("$.data.notificationSettings.serviceNotice").value(true))
        .andExpect(jsonPath("$.data.notificationSettings.marketing").value(false));
  }

  @Test
  void exposesNullableProfileFieldsWithoutFailing() throws Exception {
    authenticate(OTHER_USER_ID);

    mockMvc
        .perform(get("/api/v1/users/me"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.email").doesNotExist())
        .andExpect(jsonPath("$.data.profileImageUrl").doesNotExist())
        .andExpect(jsonPath("$.data.lastLoginAt").doesNotExist())
        .andExpect(jsonPath("$.data.createdAt").value("2026-07-02T00:00:00Z"));
  }

  @Test
  void returnsDeletedAccountStatusInsteadOfFailingOnEnumMismatch() throws Exception {
    jdbcTemplate.update("UPDATE users SET account_status = 'DELETED' WHERE id = ?", USER_ID);

    mockMvc
        .perform(get("/api/v1/users/me"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.accountStatus").value("DELETED"));
  }

  @Test
  void returnsNotFoundWhenAuthenticatedUserRowIsGone() throws Exception {
    authenticate(MISSING_USER_ID);

    mockMvc
        .perform(get("/api/v1/users/me"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("USER_404_001"));
  }

  @Test
  void requiresAuthenticationForEveryProfileEndpoint() throws Exception {
    SecurityContextHolder.clearContext();

    mockMvc.perform(get("/api/v1/users/me")).andExpect(status().isUnauthorized());
    mockMvc
        .perform(
            patch("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"nickname\":\"새이름\"}"))
        .andExpect(status().isUnauthorized());
    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isUnauthorized());
  }

  // ---------------------------------------------------------------- 313·325 내 정보 수정

  @Test
  void updatesOnlyNicknameAndKeepsRemainingProfile() throws Exception {
    mockMvc
        .perform(
            patch("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"nickname\":\"새별이맘\"}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.nickname").value("새별이맘"))
        .andExpect(jsonPath("$.data.profileImageUrl").value("https://cdn.example.com/me.png"))
        .andExpect(jsonPath("$.data.accountStatus").value("ACTIVE"));

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT nickname, profile_image_url, account_status FROM users WHERE id = ?",
                USER_ID))
        .containsEntry("nickname", "새별이맘")
        .containsEntry("profile_image_url", "https://cdn.example.com/me.png")
        .containsEntry("account_status", "ACTIVE");
  }

  @Test
  void keepsNicknameWhenRequestOmitsIt() throws Exception {
    mockMvc
        .perform(patch("/api/v1/users/me").contentType(MediaType.APPLICATION_JSON).content("{}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.nickname").value("별이맘"));
  }

  @Test
  void acceptsProfileImageFileIdWithoutApplyingIt() throws Exception {
    mockMvc
        .perform(
            patch("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"profileImageFileId\":\"file-123\"}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.profileImageUrl").value("https://cdn.example.com/me.png"));

    // 사전 업로드 연결 기반이 없어 이미지 식별자는 계약 호환용으로만 받는다.
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT profile_image_url FROM users WHERE id = ?", String.class, USER_ID))
        .isEqualTo("https://cdn.example.com/me.png");
  }

  @Test
  void rejectsNicknameLongerThanTheContractLimit() throws Exception {
    mockMvc
        .perform(
            patch("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"nickname\":\"" + "가".repeat(51) + "\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT nickname FROM users WHERE id = ?", String.class, USER_ID))
        .isEqualTo("별이맘");
  }

  // ---------------------------------------------------------------- 315·327 회원 탈퇴

  /**
   * S15P11B209-728 — 탈퇴가 단독 보유 아동을 함께 정리하는지 실 DB로 확인한다.
   *
   * <p>이 테스트는 원래 {@code deletesAccountWithIdentityRowsAndKeepsChildData}였다. 즉 <b>아동 데이터를 남기는 것이 의도된
   * 동작</b>으로 단언하고 있었다. 그런데 그 상태에서는 아동 프로필·그림·음성이 보호자와 끊긴 채 남아 이후 누구도 삭제를 요청할 수 없었고, CLAUDE.md
   * 9절("회원 탈퇴 시 아동 데이터 함께 삭제")과 어긋났다.
   *
   * <p>아동 행 자체는 <b>남는 것이 맞다</b> — 개별 삭제 API와 같은 소프트 삭제 정책이라, 행을 지우는 대신 {@code
   * profile_status='DELETED'}로 표시하고 스토리지 삭제를 큐에 넣는다. 그래서 "행이 있다"만 보는 검증은 삭제 여부를 구분하지 못한다 — 상태까지 봐야
   * 한다.
   */
  @Test
  void deletesAccountAndSoftDeletesSolelyOwnedChild() throws Exception {
    jdbcTemplate.update(
        "INSERT INTO auth_accounts (user_id, provider, provider_subject) "
            + "VALUES (?, 'KAKAO', 'kakao-42-subject')",
        USER_ID);
    jdbcTemplate.update("INSERT INTO user_notification_settings (user_id) VALUES (?)", USER_ID);
    jdbcTemplate.update(
        "INSERT INTO consent_terms "
            + "(id, term_code, target_scope, is_required, version, title, effective_at, is_active) "
            + "VALUES (1, 'SERVICE_TOS', 'USER', TRUE, 'v1', '서비스 이용약관', "
            + "'2020-01-01 00:00:00', TRUE)");
    jdbcTemplate.update(
        "INSERT INTO consent_records "
            + "(consent_term_id, actor_user_id, subject_child_id, subject_reference_hash, action) "
            + "VALUES (1, ?, NULL, REPEAT('a', 64), 'AGREE')",
        USER_ID);

    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNoContent());

    assertThat(count("SELECT COUNT(*) FROM users WHERE id = " + USER_ID)).isZero();
    assertThat(count("SELECT COUNT(*) FROM auth_accounts WHERE user_id = " + USER_ID)).isZero();
    assertThat(count("SELECT COUNT(*) FROM user_notification_settings WHERE user_id = " + USER_ID))
        .isZero();
    assertThat(
            count(
                "SELECT COUNT(*) FROM guardian_child_relations WHERE guardian_user_id = "
                    + USER_ID))
        .isZero();
    // 아동 행은 남는다 — 소프트 삭제이기 때문이다. 행 존재만 보면 삭제 여부를 구분하지 못한다.
    assertThat(count("SELECT COUNT(*) FROM children WHERE id = " + CHILD_ID)).isEqualTo(1);
    // ★ 실제 판정은 상태다. 단독 보유 아동이므로 DELETED 로 표시되고 삭제 시각이 찍혀야 한다.
    assertThat(
            count(
                "SELECT COUNT(*) FROM children WHERE id = "
                    + CHILD_ID
                    + " AND profile_status = 'DELETED' AND deleted_at IS NOT NULL"))
        .isEqualTo(1);
    // 공동 보호자가 없는 아동만 대상이다. 다른 보호자에게 걸린 아동은 건드리지 않는다.
    assertThat(
            count(
                "SELECT COUNT(*) FROM children WHERE id = "
                    + OTHER_CHILD_ID
                    + " AND profile_status = 'ACTIVE'"))
        .isEqualTo(1);
    // 동의 이력은 행위자만 비식별화한다(법적 보존 대상).
    assertThat(count("SELECT COUNT(*) FROM consent_records WHERE actor_user_id IS NULL"))
        .isEqualTo(1);
  }

  /**
   * S15P11B209-728 — 전문가도 탈퇴할 수 있어야 한다(2026-07-30 결정).
   *
   * <p>{@code expert_profiles.user_id}가 {@code ON DELETE RESTRICT}라, 전문가 프로필을 남겨둔 채 사용자를 지우면 DB 제약
   * 위반이 500으로 샌다. 탈퇴 처리에서 프로필을 먼저 지워 경로를 연다.
   *
   * <p>이 테스트는 <b>V22 마이그레이션도 함께 검증</b>한다. 미술 활동 자료가 {@code ON DELETE SET NULL}로 바뀌지 않았다면 프로필 삭제가 그
   * FK에 걸려 여전히 500이 난다.
   */
  @Test
  void allowsWithdrawalForExpertAndKeepsAuthoredMaterial() throws Exception {
    jdbcTemplate.update(
        "INSERT INTO expert_profiles (id, user_id, display_name, career_years, verification_status) "
            + "VALUES (900, ?, '김상담', 5, 'VERIFIED')",
        USER_ID);
    jdbcTemplate.update(
        "INSERT INTO activity_templates "
            + "(id, expert_profile_id, title, content, age_group, activity_type) "
            + "VALUES (900, 900, '자료 제목', '자료 내용', 'AGE_5_7', 'DRAWING')");

    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNoContent());

    assertThat(count("SELECT COUNT(*) FROM users WHERE id = " + USER_ID)).isZero();
    assertThat(count("SELECT COUNT(*) FROM expert_profiles WHERE id = 900")).isZero();
    // 미술 자료는 남고 작성자만 끊긴다 — 보호자에게 제공되는 콘텐츠이기 때문이다.
    assertThat(count("SELECT COUNT(*) FROM activity_templates WHERE id = 900")).isEqualTo(1);
    assertThat(
            count(
                "SELECT COUNT(*) FROM activity_templates WHERE id = 900 AND expert_profile_id IS NULL"))
        .isEqualTo(1);
  }

  @Test
  void rejectsWithdrawalWhenConfirmationDoesNotMatch() throws Exception {
    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"delete\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("USER_400_002"));

    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"  \"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    assertThat(count("SELECT COUNT(*) FROM users WHERE id = " + USER_ID)).isEqualTo(1);
  }

  @Test
  void returnsNotFoundWhenWithdrawingTwice() throws Exception {
    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNoContent());

    mockMvc
        .perform(
            delete("/api/v1/users/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("USER_404_001"));
  }

  // ---------------------------------------------------------------- 555 알림 설정 수정

  @Test
  void insertsNotificationSettingsRowWhenNoneExistsOnUpdate() throws Exception {
    assertThat(count("SELECT COUNT(*) FROM user_notification_settings WHERE user_id = " + USER_ID))
        .isZero();

    mockMvc
        .perform(
            patch("/api/v1/users/me/notification-settings")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "analysisCompleted": false,
                      "community": false,
                      "serviceNotice": true,
                      "marketing": true
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.analysisCompleted").value(false))
        .andExpect(jsonPath("$.data.community").value(false))
        .andExpect(jsonPath("$.data.serviceNotice").value(true))
        .andExpect(jsonPath("$.data.marketing").value(true));

    assertThat(count("SELECT COUNT(*) FROM user_notification_settings WHERE user_id = " + USER_ID))
        .isEqualTo(1);
    assertThat(notificationSetting("analysis_completed")).isFalse();
    assertThat(notificationSetting("community")).isFalse();
    assertThat(notificationSetting("service_notice")).isTrue();
    assertThat(notificationSetting("marketing")).isTrue();
  }

  @Test
  void updatesExistingNotificationSettingsRowAndKeepsSingleRow() throws Exception {
    jdbcTemplate.update(
        "INSERT INTO user_notification_settings "
            + "(user_id, analysis_completed, community, service_notice, marketing) "
            + "VALUES (?, TRUE, TRUE, TRUE, FALSE)",
        USER_ID);

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
        .andExpect(jsonPath("$.data.analysisCompleted").value(false))
        .andExpect(jsonPath("$.data.community").value(true))
        .andExpect(jsonPath("$.data.serviceNotice").value(false))
        .andExpect(jsonPath("$.data.marketing").value(true));

    assertThat(count("SELECT COUNT(*) FROM user_notification_settings WHERE user_id = " + USER_ID))
        .isEqualTo(1);
    assertThat(notificationSetting("analysis_completed")).isFalse();
    assertThat(notificationSetting("community")).isTrue();
    assertThat(notificationSetting("service_notice")).isFalse();
    assertThat(notificationSetting("marketing")).isTrue();
  }

  @Test
  void rejectsNotificationSettingsUpdateMissingRequiredField() throws Exception {
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

    assertThat(count("SELECT COUNT(*) FROM user_notification_settings WHERE user_id = " + USER_ID))
        .isZero();
  }

  // ---------------------------------------------------------------- 564 데이터 보관 정책 조회

  @Test
  void returnsProvisionalDefaultRetentionPolicyWhenNoSettingsRowExists() throws Exception {
    assertThat(
            count("SELECT COUNT(*) FROM user_data_retention_settings WHERE user_id = " + USER_ID))
        .isZero();

    mockMvc
        .perform(get("/api/v1/users/me/data-retention"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.retentionDays").value(180))
        .andExpect(jsonPath("$.data.noticeDaysBefore").value(30))
        .andExpect(jsonPath("$.data.policyStatus").value("PROVISIONAL"));

    // 조회는 행을 만들지 않는다. 만들면 이후 정책 수치 변경이 사용자별로 고정돼 버린다.
    assertThat(
            count("SELECT COUNT(*) FROM user_data_retention_settings WHERE user_id = " + USER_ID))
        .isZero();
  }

  @Test
  void returnsStoredRetentionPolicyForTheAuthenticatedUserOnly() throws Exception {
    jdbcTemplate.update(
        "INSERT INTO user_data_retention_settings "
            + "(user_id, retention_days, notice_days_before) VALUES (?, 365, 14), (?, 90, 7)",
        USER_ID,
        OTHER_USER_ID);

    mockMvc
        .perform(get("/api/v1/users/me/data-retention"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.retentionDays").value(365))
        .andExpect(jsonPath("$.data.noticeDaysBefore").value(14))
        .andExpect(jsonPath("$.data.policyStatus").value("PROVISIONAL"));
  }

  // ---------------------------------------------------------------- 345~348 아동 범위 동의

  @Test
  void reportsChildScopeConsentStatusForLinkedGuardian() throws Exception {
    insertUserAndChildTerms();
    agree(1, null, "a");
    agree(2, CHILD_ID, "b");

    mockMvc
        .perform(get("/api/v1/consents").param("childId", String.valueOf(CHILD_ID)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.childId").value(CHILD_ID))
        .andExpect(jsonPath("$.data.requiredConsentsSatisfied").value(true))
        .andExpect(jsonPath("$.data.items.length()").value(3));
  }

  @Test
  void reportsRequiredChildConsentAsUnsatisfiedWhenWithdrawn() throws Exception {
    insertUserAndChildTerms();
    agree(1, null, "a");
    agree(2, CHILD_ID, "b");
    jdbcTemplate.update(
        "INSERT INTO consent_records "
            + "(consent_term_id, actor_user_id, subject_child_id, subject_reference_hash, action, "
            + "recorded_at) VALUES (2, ?, ?, REPEAT('b', 64), 'WITHDRAW', "
            + "DATE_ADD(UTC_TIMESTAMP(6), INTERVAL 1 SECOND))",
        USER_ID,
        CHILD_ID);

    mockMvc
        .perform(get("/api/v1/consents").param("childId", String.valueOf(CHILD_ID)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.requiredConsentsSatisfied").value(false));
  }

  @Test
  void rejectsChildScopeConsentAccessForUnlinkedGuardian() throws Exception {
    insertUserAndChildTerms();

    mockMvc
        .perform(get("/api/v1/consents").param("childId", String.valueOf(OTHER_CHILD_ID)))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("CONSENT_403_002"));

    mockMvc
        .perform(get("/api/v1/consents/history").param("childId", String.valueOf(OTHER_CHILD_ID)))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("CONSENT_403_002"));
  }

  @Test
  void appendsOptionalChildConsentChangeAndExposesItInHistory() throws Exception {
    insertUserAndChildTerms();
    agree(3, CHILD_ID, "c");

    mockMvc
        .perform(
            patch("/api/v1/consents")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "childId": %d,
                      "agreements": [{"termId": 3, "action": "WITHDRAW"}]
                    }
                    """
                        .formatted(CHILD_ID)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.recordedCount").value(1));

    assertThat(count("SELECT COUNT(*) FROM consent_records WHERE consent_term_id = 3"))
        .isEqualTo(2);

    mockMvc
        .perform(
            get("/api/v1/consents/history")
                .param("childId", String.valueOf(CHILD_ID))
                .param("termCode", "CHILD_MARKETING"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(2))
        .andExpect(jsonPath("$.data.content[0].action").value("WITHDRAW"))
        .andExpect(jsonPath("$.data.content[1].action").value("AGREE"));
  }

  @Test
  void rejectsChangingRequiredTermThroughOptionalConsentApi() throws Exception {
    insertUserAndChildTerms();

    mockMvc
        .perform(
            patch("/api/v1/consents")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "childId": %d,
                      "agreements": [{"termId": 2, "action": "WITHDRAW"}]
                    }
                    """
                        .formatted(CHILD_ID)))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("CONSENT_400_002"));

    assertThat(count("SELECT COUNT(*) FROM consent_records WHERE consent_term_id = 2")).isZero();
  }

  @Test
  void rejectsConsentHistoryQueryOutsideAllowedRange() throws Exception {
    insertUserAndChildTerms();

    mockMvc
        .perform(
            get("/api/v1/consents/history").param("from", "2026-07-25").param("to", "2026-07-01"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    mockMvc
        .perform(get("/api/v1/consents/history").param("size", "101"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    mockMvc
        .perform(get("/api/v1/consents/history").param("page", "-1"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  // ---------------------------------------------------------------- fixture 도우미

  private void insertUserAndChildTerms() {
    jdbcTemplate.update(
        "INSERT INTO consent_terms "
            + "(id, term_code, target_scope, is_required, version, title, effective_at, is_active) "
            + "VALUES (1, 'SERVICE_TOS', 'USER', TRUE, 'v1', '서비스 이용약관', "
            + "'2020-01-01 00:00:00', TRUE), "
            + "(2, 'VOICE_PROCESSING', 'CHILD', TRUE, 'v1', '음성 처리 동의', "
            + "'2020-01-01 00:00:00', TRUE), "
            + "(3, 'CHILD_MARKETING', 'CHILD', FALSE, 'v1', '아동 마케팅 동의', "
            + "'2020-01-01 00:00:00', TRUE)");
  }

  private void agree(long termId, Long childId, String hashSeed) {
    jdbcTemplate.update(
        "INSERT INTO consent_records "
            + "(consent_term_id, actor_user_id, subject_child_id, subject_reference_hash, action) "
            + "VALUES (?, ?, ?, REPEAT(?, 64), 'AGREE')",
        termId,
        USER_ID,
        childId,
        hashSeed);
  }

  private int count(String sql) {
    return jdbcTemplate.queryForObject(sql, Integer.class);
  }

  private boolean notificationSetting(String column) {
    return Boolean.TRUE.equals(
        jdbcTemplate.queryForObject(
            "SELECT " + column + " FROM user_notification_settings WHERE user_id = ?",
            Boolean.class,
            USER_ID));
  }

  private void authenticate(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
