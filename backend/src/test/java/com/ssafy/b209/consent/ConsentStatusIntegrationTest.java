package com.ssafy.b209.consent;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class ConsentStatusIntegrationTest {

  private static final Long USER_ID = 41L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    setAuthenticatedUser(USER_ID);
    jdbcTemplate.update("DELETE FROM consent_records");
    jdbcTemplate.update("DELETE FROM consent_terms");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, account_status, is_completed) "
            + "VALUES (?, 'GUARDIAN', 'ACTIVE', TRUE)",
        USER_ID);
    jdbcTemplate.update(
        "INSERT INTO consent_terms "
            + "(id, term_code, target_scope, is_required, version, title, effective_at, is_active) "
            + "VALUES (1, 'SERVICE_TOS', 'USER', TRUE, 'v1', '서비스 이용약관', "
            + "'2020-01-01 00:00:00', TRUE), "
            + "(2, 'MARKETING', 'USER', FALSE, 'v1', '마케팅 수신', '2020-01-01 00:00:00', TRUE)");
    // 필수 약관: AGREE. 선택 약관: AGREE 후 WITHDRAW → 최신은 WITHDRAW.
    jdbcTemplate.update(
        "INSERT INTO consent_records "
            + "(consent_term_id, actor_user_id, subject_child_id, subject_reference_hash, action) "
            + "VALUES (1, ?, NULL, REPEAT('a', 64), 'AGREE'), "
            + "(2, ?, NULL, REPEAT('b', 64), 'AGREE'), "
            + "(2, ?, NULL, REPEAT('b', 64), 'WITHDRAW')",
        USER_ID,
        USER_ID,
        USER_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void reportsLatestConsentStatusPerTermAndRequiredSatisfaction() throws Exception {
    mockMvc
        .perform(get("/api/v1/consents"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.requiredConsentsSatisfied").value(true))
        .andExpect(jsonPath("$.data.items.length()").value(2))
        .andExpect(jsonPath("$.data.items[0].termId").value(1))
        .andExpect(jsonPath("$.data.items[0].required").value(true))
        .andExpect(jsonPath("$.data.items[0].agreed").value(true))
        .andExpect(jsonPath("$.data.items[1].termId").value(2))
        .andExpect(jsonPath("$.data.items[1].required").value(false))
        .andExpect(jsonPath("$.data.items[1].agreed").value(false));
  }

  private void setAuthenticatedUser(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
