package com.ssafy.b209.child;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
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
import org.springframework.http.MediaType;
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
    jdbcTemplate.update("DELETE FROM storage_deletion_jobs");
    jdbcTemplate.update("DELETE FROM drawing_assets");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.update("DELETE FROM drawing_types");
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
  void returnsChildDetailWithResponseModesAndRelationship() throws Exception {
    jdbcTemplate.update(
        "UPDATE children SET preferred_character = 'MONGLE', "
            + "profile_image_url = 'https://cdn.example.com/child-1.png' WHERE id = 1");
    jdbcTemplate.update(
        "INSERT INTO child_response_modes (child_id, response_mode, display_order) "
            + "VALUES (1, 'VOICE', 1), (1, 'EMOJI', 0)");
    int expectedAge =
        java.time.Period.between(java.time.LocalDate.of(2018, 5, 10), java.time.LocalDate.now())
            .getYears();

    mockMvc
        .perform(get("/api/v1/children/1"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.childId").value(1))
        .andExpect(jsonPath("$.data.nickname").value("child-one"))
        .andExpect(jsonPath("$.data.birthDate").value("2018-05-10"))
        .andExpect(jsonPath("$.data.age").value(expectedAge))
        .andExpect(jsonPath("$.data.profileImageUrl").value("https://cdn.example.com/child-1.png"))
        .andExpect(jsonPath("$.data.preferredCharacter").value("MONGLE"))
        .andExpect(jsonPath("$.data.questionDifficulty").value("LOWER_ELEMENTARY"))
        .andExpect(jsonPath("$.data.responseModes[0]").value("EMOJI"))
        .andExpect(jsonPath("$.data.responseModes[1]").value("VOICE"))
        .andExpect(jsonPath("$.data.tutorialStatus").value("NOT_STARTED"))
        .andExpect(jsonPath("$.data.profileStatus").value("ACTIVE"))
        .andExpect(jsonPath("$.data.relationshipType").value("MOTHER"))
        .andExpect(jsonPath("$.data.createdAt").exists());
  }

  @Test
  void hidesDeletedAndUnlinkedChildrenFromDetailWithTheSameNotFound() throws Exception {
    for (long childId : List.of(3L, 4L, 999L)) {
      mockMvc
          .perform(get("/api/v1/children/{childId}", childId))
          .andExpect(status().isNotFound())
          .andExpect(jsonPath("$.code").value("CHILD_404_001"));
    }
  }

  @Test
  void requiresAuthenticationForChildDetail() throws Exception {
    SecurityContextHolder.clearContext();

    mockMvc
        .perform(get("/api/v1/children/1"))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
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
  void summarizesRecentActivityFromNonDeletedDrawingSessions() throws Exception {
    jdbcTemplate.update(
        """
        INSERT INTO drawing_types (id, code, name, activity_category, selectable_by)
        VALUES (101, 'RECENT_ACTIVITY_TEST', '최근 활동 테스트', 'GENERAL', 'GUARDIAN')
        """);
    jdbcTemplate.update(
        """
        INSERT INTO drawing_sessions
          (id, child_id, drawing_type_id, input_method, session_status, current_stage,
           started_at, deleted_at)
        VALUES
          (201, 1, 101, 'CANVAS', 'IN_PROGRESS', 'DRAWING', '2026-07-18 09:00:00', NULL),
          (202, 1, 101, 'CANVAS', 'COMPLETED', 'COMPLETED', '2026-07-20 08:15:00', NULL),
          (203, 1, 101, 'CANVAS', 'DELETED', 'DRAWING', '2026-07-21 10:00:00', '2026-07-21 11:00:00')
        """);

    mockMvc
        .perform(get("/api/v1/children"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data[0].childId").value(1))
        .andExpect(jsonPath("$.data[0].recentActivity.totalActivityCount").value(2))
        .andExpect(
            jsonPath("$.data[0].recentActivity.lastActivityAt").value("2026-07-20T08:15:00Z"))
        .andExpect(jsonPath("$.data[1].childId").value(2))
        .andExpect(jsonPath("$.data[1].recentActivity.totalActivityCount").value(0))
        .andExpect(jsonPath("$.data[1].recentActivity.lastActivityAt").value(nullValue()));
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

  @Test
  void softDeletesTheOnlyGuardiansChildAndSchedulesItsStoredDrawing() throws Exception {
    jdbcTemplate.update(
        """
        INSERT INTO drawing_types
          (id, code, name, activity_category, selectable_by)
        VALUES (101, 'DELETE_TEST', '삭제 테스트', 'GENERAL', 'GUARDIAN')
        """);
    jdbcTemplate.update(
        """
        INSERT INTO drawing_sessions
          (id, child_id, drawing_type_id, started_by_user_id, input_method)
        VALUES (201, 1, 101, ?, 'CANVAS')
        """,
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        """
        INSERT INTO drawing_assets
          (id, drawing_session_id, asset_type, storage_key, mime_type,
           file_size_bytes, checksum_sha256, captured_at)
        VALUES
          (301, 201, 'DRAFT', 'children/1/draft.png', 'image/png', 10,
           'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
           CURRENT_TIMESTAMP(6))
        """);

    mockMvc
        .perform(
            delete("/api/v1/children/1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNoContent());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT profile_status FROM children WHERE id = 1", String.class))
        .isEqualTo("DELETED");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT deleted_at IS NOT NULL FROM children WHERE id = 1", Boolean.class))
        .isTrue();
    assertThat(
            jdbcTemplate.queryForObject(
                """
                SELECT COUNT(*)
                  FROM storage_deletion_jobs
                 WHERE storage_key = 'children/1/draft.png'
                   AND resource_type = 'DRAWING_ASSET'
                   AND resource_id = 301
                   AND deletion_status = 'PENDING'
                """,
                Integer.class))
        .isEqualTo(1);
  }

  @Test
  void rejectsChildDeletionWithoutConfirmationBodyAndKeepsProfileActive() throws Exception {
    mockMvc
        .perform(delete("/api/v1/children/1"))
        .andExpect(status().isBadRequest())
        // 본문 누락도 확인 값 오류와 같은 코드로 응답한다(CHILD-05 계약 통일).
        .andExpect(jsonPath("$.code").value("CHILD_400_002"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT profile_status FROM children WHERE id = 1", String.class))
        .isEqualTo("ACTIVE");
  }

  @Test
  void rejectsUnsupportedCascadeQueryAndKeepsProfileActive() throws Exception {
    mockMvc
        .perform(
            delete("/api/v1/children/1")
                .queryParam("cascade", "true")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isBadRequest())
        // 삭제 범위는 서버 정책으로 고정하므로 cascade를 무시하지 않고 거부한다.
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT profile_status FROM children WHERE id = 1", String.class))
        .isEqualTo("ACTIVE");
  }

  @Test
  void rejectsWholeChildDeletionWhenAnotherGuardianIsConnected() throws Exception {
    jdbcTemplate.update(
        """
        INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type)
        VALUES (?, 1, 'FATHER')
        """,
        OTHER_GUARDIAN_USER_ID);

    mockMvc
        .perform(
            delete("/api/v1/children/1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("CHILD_409_001"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT profile_status FROM children WHERE id = 1", String.class))
        .isEqualTo("ACTIVE");
  }

  private void setAuthenticatedUser(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
