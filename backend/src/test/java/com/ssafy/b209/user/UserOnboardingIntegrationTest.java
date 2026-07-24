package com.ssafy.b209.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.util.List;
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

@AutoConfigureMockMvc
class UserOnboardingIntegrationTest extends IntegrationTestSupport {

  private static final Long USER_ID = 51L;

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    setAuthenticatedUser(USER_ID);
    jdbcTemplate.update(
        "INSERT INTO users (id, role, account_status, is_completed) "
            + "VALUES (?, NULL, 'PENDING', FALSE)",
        USER_ID);
    jdbcTemplate.update(
        "INSERT INTO consent_terms "
            + "(id, term_code, target_scope, is_required, version, title, effective_at, is_active) "
            + "VALUES (1, 'SERVICE_TOS', 'USER', TRUE, 'v1', '서비스 이용약관', "
            + "'2020-01-01 00:00:00', TRUE)");
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void completesOnboardingPersistsUserStateAndConsent() throws Exception {
    mockMvc
        .perform(
            put("/api/v1/users/me/onboarding")
                .contentType(MediaType.APPLICATION_JSON)
                .content(onboardingJson()))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.role").value("GUARDIAN"))
        .andExpect(jsonPath("$.data.email").value("guardian@example.com"))
        .andExpect(jsonPath("$.data.accountStatus").value("ACTIVE"))
        .andExpect(jsonPath("$.data.onboardingCompleted").value(true));

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT role, account_status, email FROM users WHERE id = ?", USER_ID))
        .containsEntry("role", "GUARDIAN")
        .containsEntry("account_status", "ACTIVE")
        .containsEntry("email", "guardian@example.com");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT is_completed FROM users WHERE id = ?", Boolean.class, USER_ID))
        .isTrue();
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM consent_records WHERE actor_user_id = ? AND action = 'AGREE'",
                Integer.class,
                USER_ID))
        .isEqualTo(1);
  }

  @Test
  void isIdempotentForAnAlreadyOnboardedUser() throws Exception {
    mockMvc
        .perform(
            put("/api/v1/users/me/onboarding")
                .contentType(MediaType.APPLICATION_JSON)
                .content(onboardingJson()))
        .andExpect(status().isOk());

    mockMvc
        .perform(
            put("/api/v1/users/me/onboarding")
                .contentType(MediaType.APPLICATION_JSON)
                .content(onboardingJson()))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.onboardingCompleted").value(true));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM consent_records WHERE actor_user_id = ?",
                Integer.class,
                USER_ID))
        .isEqualTo(1);
  }

  @Test
  void rejectsOnboardingWhenRequiredConsentIsMissingAndKeepsUserPending() throws Exception {
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
                      "consents": []
                    }
                    """))
        .andExpect(status().isForbidden());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT account_status FROM users WHERE id = ?", String.class, USER_ID))
        .isEqualTo("PENDING");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT is_completed FROM users WHERE id = ?", Boolean.class, USER_ID))
        .isFalse();
  }

  private String onboardingJson() {
    return """
        {
          "role": "GUARDIAN",
          "nickname": "튼튼이엄마",
          "email": "guardian@example.com",
          "consents": [{"termId": 1, "action": "AGREE"}]
        }
        """;
  }

  private void setAuthenticatedUser(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
