package com.ssafy.b209.child;

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
class ChildListIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long OTHER_GUARDIAN_USER_ID = 42L;

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
    setAuthenticatedUser(GUARDIAN_USER_ID);
    jdbcTemplate.update("DELETE FROM child_response_modes");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'list-guardian', 'ACTIVE'), "
            + "(?, 'GUARDIAN', 'other-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status, "
            + "created_at) "
            + "VALUES (1, 'child-one', '2018-05-10', 'LOWER_ELEMENTARY', 'NOT_STARTED', 'ACTIVE', "
            + "'2026-07-20 01:00:00'), "
            + "(2, 'child-two', '2016-01-01', 'UPPER_ELEMENTARY', 'COMPLETED', 'ACTIVE', "
            + "'2026-07-20 02:00:00'), "
            + "(3, 'deleted-child', '2017-01-01', 'PRESCHOOL', 'NOT_STARTED', 'DELETED', "
            + "'2026-07-20 03:00:00'), "
            + "(4, 'other-child', '2019-01-01', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE', "
            + "'2026-07-20 04:00:00')");
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, 1, 'MOTHER'), (?, 2, 'FATHER'), (?, 3, 'MOTHER'), (?, 4, 'MOTHER')",
        GUARDIAN_USER_ID,
        GUARDIAN_USER_ID,
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void listsOnlyActiveConnectedChildrenInRegistrationOrder() throws Exception {
    mockMvc
        .perform(get("/api/v1/children"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.length()").value(2))
        .andExpect(jsonPath("$.data[0].childId").value(1))
        .andExpect(jsonPath("$.data[0].nickname").value("child-one"))
        .andExpect(jsonPath("$.data[0].relationshipType").value("MOTHER"))
        .andExpect(jsonPath("$.data[1].childId").value(2))
        .andExpect(jsonPath("$.data[1].relationshipType").value("FATHER"));
  }

  @Test
  void returnsAnEmptyListForAGuardianWithoutConnectedChildren() throws Exception {
    setAuthenticatedUser(OTHER_GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "DELETE FROM guardian_child_relations WHERE guardian_user_id = ?", OTHER_GUARDIAN_USER_ID);

    mockMvc
        .perform(get("/api/v1/children"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data").isArray())
        .andExpect(jsonPath("$.data").isEmpty());
  }

  private void setAuthenticatedUser(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
