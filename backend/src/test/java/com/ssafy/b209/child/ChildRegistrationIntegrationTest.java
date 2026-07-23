package com.ssafy.b209.child;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import java.time.LocalDate;
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
class ChildRegistrationIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;

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
    setAuthenticatedGuardian();
    jdbcTemplate.update("DELETE FROM child_response_modes");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.execute("ALTER TABLE children AUTO_INCREMENT = 1");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'child-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void registersAChildAndPersistsTheRelationAndResponseModes() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/children")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "nickname": "별이",
                      "birthDate": "2018-05-10",
                      "relationshipType": "MOTHER",
                      "preferredCharacter": "MONGLE",
                      "questionDifficulty": "LOWER_ELEMENTARY",
                      "responseModes": ["VOICE", "EMOJI"]
                    }
                    """))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/children/1"))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.childId").value(1))
        .andExpect(jsonPath("$.data.nickname").value("별이"))
        .andExpect(jsonPath("$.data.age").isNumber())
        .andExpect(jsonPath("$.data.relationshipType").value("MOTHER"))
        .andExpect(jsonPath("$.data.responseModes[0]").value("VOICE"))
        .andExpect(jsonPath("$.data.responseModes[1]").value("EMOJI"))
        .andExpect(jsonPath("$.data.tutorialStatus").value("NOT_STARTED"))
        .andExpect(jsonPath("$.data.profileStatus").value("ACTIVE"));

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT nickname, question_difficulty, tutorial_status, profile_status, "
                    + "preferred_character, profile_image_url "
                    + "FROM children WHERE id = 1"))
        .containsEntry("nickname", "별이")
        .containsEntry("question_difficulty", "LOWER_ELEMENTARY")
        .containsEntry("tutorial_status", "NOT_STARTED")
        .containsEntry("profile_status", "ACTIVE")
        .containsEntry("preferred_character", "MONGLE")
        .containsEntry("profile_image_url", null);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT relationship_type FROM guardian_child_relations "
                    + "WHERE guardian_user_id = ? AND child_id = 1",
                String.class,
                GUARDIAN_USER_ID))
        .isEqualTo("MOTHER");
    assertThat(
            jdbcTemplate.queryForList(
                "SELECT response_mode FROM child_response_modes "
                    + "WHERE child_id = 1 ORDER BY display_order",
                String.class))
        .containsExactly("VOICE", "EMOJI");
  }

  @Test
  void rejectsAChildOutsideTheAllowedAgeRangeWithoutPersisting() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/children")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "nickname": "아기",
                      "birthDate": "2024-01-01",
                      "relationshipType": "MOTHER",
                      "questionDifficulty": "PRESCHOOL",
                      "responseModes": ["VOICE"]
                    }
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("CHILD_400_001"));

    assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM children", Integer.class))
        .isZero();
  }

  @Test
  void updatesTheProfileRelationAndNormalizedResponseModesAtomically() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/children")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "nickname": "별이",
                      "birthDate": "2019-03-15",
                      "relationshipType": "MOTHER",
                      "preferredCharacter": "MONGLE",
                      "questionDifficulty": "LOWER_ELEMENTARY",
                      "responseModes": ["VOICE", "COLOR"]
                    }
                    """))
        .andExpect(status().isCreated());

    mockMvc
        .perform(
            patch("/api/v1/children/1")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "nickname": "새별이",
                      "relationshipType": "FATHER",
                      "questionDifficulty": "UPPER_ELEMENTARY",
                      "responseModes": ["EMOJI", "VOICE", "EMOJI"]
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.nickname").value("새별이"))
        .andExpect(jsonPath("$.data.birthDate").value("2019-03-15"))
        .andExpect(jsonPath("$.data.relationshipType").value("FATHER"))
        .andExpect(jsonPath("$.data.questionDifficulty").value("UPPER_ELEMENTARY"))
        .andExpect(jsonPath("$.data.responseModes[0]").value("EMOJI"))
        .andExpect(jsonPath("$.data.responseModes[1]").value("VOICE"));

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT nickname, birth_date, preferred_character, question_difficulty "
                    + "FROM children WHERE id = 1"))
        .containsEntry("nickname", "새별이")
        .containsEntry("birth_date", java.sql.Date.valueOf(LocalDate.of(2019, 3, 15)))
        .containsEntry("preferred_character", "MONGLE")
        .containsEntry("question_difficulty", "UPPER_ELEMENTARY");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT relationship_type FROM guardian_child_relations "
                    + "WHERE guardian_user_id = ? AND child_id = 1",
                String.class,
                GUARDIAN_USER_ID))
        .isEqualTo("FATHER");
    assertThat(
            jdbcTemplate.queryForList(
                "SELECT response_mode FROM child_response_modes "
                    + "WHERE child_id = 1 ORDER BY display_order",
                String.class))
        .containsExactly("EMOJI", "VOICE");
  }

  private void setAuthenticatedGuardian() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(GUARDIAN_USER_ID), null, List.of()));
  }
}
