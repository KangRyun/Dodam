package com.ssafy.b209.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
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
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class DrawingReflectionIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long DRAWING_SESSION_ID = 10L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_reflection")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(GUARDIAN_USER_ID), null, List.of()));
    jdbcTemplate.update("DELETE FROM drawing_session_emotions");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM drawing_types");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'reflection-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (1, 'reflection-child', '2020-07-23', 'PRESCHOOL', 'COMPLETED', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(guardian_user_id, child_id, relationship_type) VALUES (?, 1, 'MOTHER')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "VALUES (1, 'REFLECTION_TEST', 'Reflection Test', 'GENERAL', 'BOTH', TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, title, expressed_emotion_text, "
            + "session_status, current_stage, started_at) "
            + "VALUES (?, 1, 1, 'CANVAS', 'old title', 'old expression', "
            + "'IN_PROGRESS', 'CONVERSING', UTC_TIMESTAMP(6))",
        DRAWING_SESSION_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_session_emotions "
            + "(drawing_session_id, emotion_code, selection_order) VALUES (?, 'SAD', 0)",
        DRAWING_SESSION_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void replacesStoredReflectionAndPreservesEmotionOrder() throws Exception {
    mockMvc
        .perform(
            put("/api/v1/drawing-sessions/{drawingSessionId}/reflection", DRAWING_SESSION_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "title": "  우리 가족  ",
                      "selectedEmotions": ["HAPPY", "CALM"],
                      "expressedEmotionText": "  함께 있어서 좋았어  ",
                      "skipped": false
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.currentStage").value("REFLECTION"))
        .andExpect(jsonPath("$.data.selectedEmotions[0]").value("HAPPY"))
        .andExpect(jsonPath("$.data.selectedEmotions[1]").value("CALM"));

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT title, expressed_emotion_text, current_stage "
                    + "FROM drawing_sessions WHERE id = ?",
                DRAWING_SESSION_ID))
        .containsEntry("title", "우리 가족")
        .containsEntry("expressed_emotion_text", "함께 있어서 좋았어")
        .containsEntry("current_stage", "REFLECTION");
    assertThat(storedEmotions())
        .containsExactly(
            Map.of("emotion_code", "HAPPY", "selection_order", 0),
            Map.of("emotion_code", "CALM", "selection_order", 1));

    mockMvc
        .perform(
            put("/api/v1/drawing-sessions/{drawingSessionId}/reflection", DRAWING_SESSION_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "title": null,
                      "selectedEmotions": ["UNKNOWN"],
                      "expressedEmotionText": null,
                      "skipped": false
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.selectedEmotions[0]").value("UNKNOWN"));

    assertThat(storedEmotions())
        .containsExactly(Map.of("emotion_code", "UNKNOWN", "selection_order", 0));
  }

  private List<Map<String, Object>> storedEmotions() {
    return jdbcTemplate.queryForList(
        "SELECT emotion_code, selection_order FROM drawing_session_emotions "
            + "WHERE drawing_session_id = ? ORDER BY selection_order",
        DRAWING_SESSION_ID);
  }
}
