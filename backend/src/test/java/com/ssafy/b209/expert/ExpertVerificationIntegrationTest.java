package com.ssafy.b209.expert;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.support.IntegrationTestSupport;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;

/** 관리자 전문가 승인·반려 API의 권한과 상태·감사·알림 저장을 실제 MySQL로 검증한다. */
@AutoConfigureMockMvc
class ExpertVerificationIntegrationTest extends IntegrationTestSupport {

  private static final long ADMIN_USER_ID = 5801L;
  private static final long EXPERT_USER_ID = 5802L;
  private static final long EXPERT_PROFILE_ID = 5803L;
  private static final long CREDENTIAL_ID = 5804L;

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    jdbcTemplate.update(
        """
        INSERT INTO users
          (id, role, account_status, is_completed, nickname, email, created_at, updated_at)
        VALUES
          (?, 'ADMIN', 'ACTIVE', TRUE, '관리자', 'admin@example.com', NOW(6), NOW(6)),
          (?, 'EXPERT', 'ACTIVE', TRUE, '전문가', 'expert@example.com', NOW(6), NOW(6))
        """,
        ADMIN_USER_ID,
        EXPERT_USER_ID);
    jdbcTemplate.update(
        """
        INSERT INTO expert_profiles
          (id, user_id, display_name, career_years, is_consultation_available,
           verification_status, created_at, updated_at)
        VALUES (?, ?, '검토 전문가', 3, FALSE, 'PENDING', NOW(6), NOW(6))
        """,
        EXPERT_PROFILE_ID,
        EXPERT_USER_ID);
    jdbcTemplate.update(
        """
        INSERT INTO expert_credentials
          (id, expert_profile_id, credential_type, license_name, issuer,
           verification_status, created_at, updated_at)
        VALUES (?, ?, 'ART_THERAPIST', '미술심리상담사', '한국상담협회',
                'PENDING', NOW(6), NOW(6))
        """,
        CREDENTIAL_ID,
        EXPERT_PROFILE_ID);
  }

  @AfterEach
  void clearAuthentication() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void adminApprovesExpertAndPersistsReviewAuditAndNotification() throws Exception {
    authenticate(ADMIN_USER_ID);

    mockMvc
        .perform(
            patch("/api/v1/admin/experts/{expertId}/verification", EXPERT_PROFILE_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "status":"VERIFIED",
                      "verifiedCredentialIds":[5804],
                      "rejectionReason":null,
                      "internalNote":"증빙 확인 완료"
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.verificationStatus").value("VERIFIED"))
        .andExpect(jsonPath("$.data.credentials[0].verificationStatus").value("VERIFIED"));

    assertThat(statusOf("expert_profiles", EXPERT_PROFILE_ID)).isEqualTo("VERIFIED");
    assertThat(statusOf("expert_credentials", CREDENTIAL_ID)).isEqualTo("VERIFIED");
    assertThat(count("expert_verification_reviews")).isEqualTo(1);
    assertThat(count("expert_verification_review_credentials")).isEqualTo(1);
    assertThat(count("audit_logs")).isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM notifications "
                    + "WHERE recipient_user_id = ? "
                    + "AND notification_type = 'EXPERT_VERIFICATION_RESULT'",
                Integer.class,
                EXPERT_USER_ID))
        .isEqualTo(1);
  }

  @Test
  void expertCannotReviewAnotherExpert() throws Exception {
    authenticate(EXPERT_USER_ID);

    mockMvc
        .perform(
            patch("/api/v1/admin/experts/{expertId}/verification", EXPERT_PROFILE_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "status":"REJECTED",
                      "verifiedCredentialIds":[],
                      "rejectionReason":"증빙 식별 불가"
                    }
                    """))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("AUTH_403_002"));

    assertThat(statusOf("expert_profiles", EXPERT_PROFILE_ID)).isEqualTo("PENDING");
    assertThat(count("expert_verification_reviews")).isZero();
  }

  private void authenticate(long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            new UsernamePasswordAuthenticationToken(
                new AuthenticatedUser(userId), null, java.util.List.of()));
  }

  private String statusOf(String table, long id) {
    return jdbcTemplate.queryForObject(
        "SELECT verification_status FROM " + table + " WHERE id = ?", String.class, id);
  }

  private int count(String table) {
    return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM " + table, Integer.class);
  }
}
