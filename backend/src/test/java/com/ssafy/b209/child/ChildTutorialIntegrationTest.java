package com.ssafy.b209.child;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
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
class ChildTutorialIntegrationTest extends IntegrationTestSupport {

  private static final long GUARDIAN_USER_ID = 41L;
  private static final long OTHER_GUARDIAN_USER_ID = 42L;

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    setAuthenticatedUser(GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'guardian', 'ACTIVE'), "
            + "(?, 'GUARDIAN', 'other', 'ACTIVE')",
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, tutorial_status, profile_status) "
            + "VALUES (1, 'child', '2019-01-01', 'NOT_STARTED', 'ACTIVE'), "
            + "(2, 'other-child', '2019-01-01', 'NOT_STARTED', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, 1, 'MOTHER'), (?, 2, 'MOTHER')",
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void progressesFromNotStartedThroughInProgressToCompleted() throws Exception {
    mockMvc
        .perform(
            patch("/api/v1/children/1/tutorial")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {"tutorialStatus":"IN_PROGRESS","lastStep":"DRAWING_GUIDE"}
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.tutorialStatus").value("IN_PROGRESS"))
        .andExpect(jsonPath("$.data.lastStep").value("DRAWING_GUIDE"))
        .andExpect(jsonPath("$.data.completedAt").doesNotExist());

    mockMvc
        .perform(
            patch("/api/v1/children/1/tutorial")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {"tutorialStatus":"COMPLETED","lastStep":"FINISH"}
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.tutorialStatus").value("COMPLETED"))
        .andExpect(jsonPath("$.data.lastStep").value("FINISH"))
        .andExpect(jsonPath("$.data.completedAt").isNotEmpty());

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT tutorial_status, tutorial_last_step, "
                    + "tutorial_completed_at IS NOT NULL AS completed "
                    + "FROM children WHERE id = 1"))
        .containsEntry("tutorial_status", "COMPLETED")
        .containsEntry("tutorial_last_step", "FINISH")
        .containsEntry("completed", 1L);
  }

  @Test
  void rejectsACompletedToInProgressRegressionWithoutChangingData() throws Exception {
    jdbcTemplate.update(
        "UPDATE children SET tutorial_status = 'COMPLETED', "
            + "tutorial_last_step = 'FINISH', tutorial_completed_at = NOW(6) WHERE id = 1");

    mockMvc
        .perform(
            patch("/api/v1/children/1/tutorial")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {"tutorialStatus":"IN_PROGRESS","lastStep":"WELCOME"}
                    """))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("CHILD_409_002"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT tutorial_status FROM children WHERE id = 1", String.class))
        .isEqualTo("COMPLETED");
  }

  @Test
  void hidesAnUnlinkedChildWithNotFound() throws Exception {
    mockMvc
        .perform(
            patch("/api/v1/children/2/tutorial")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {"tutorialStatus":"IN_PROGRESS","lastStep":"WELCOME"}
                    """))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("CHILD_404_001"));
  }

  private void setAuthenticatedUser(long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
