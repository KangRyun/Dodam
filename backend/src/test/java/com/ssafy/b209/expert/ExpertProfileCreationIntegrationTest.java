package com.ssafy.b209.expert;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
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

/** 전문가 프로필 생성 API의 인증·검증·DB 저장 계약을 실제 MySQL로 검증한다. */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class ExpertProfileCreationIntegrationTest {

  private static final long EXPERT_USER_ID = 5741L;
  private static final long GUARDIAN_USER_ID = 5742L;
  private static final long VERIFIED_EXPERT_USER_ID = 5743L;
  private static final long VERIFIED_EXPERT_PROFILE_ID = 5751L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_expert")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    jdbcTemplate.update("DELETE FROM expert_follows");
    jdbcTemplate.update("DELETE FROM expert_profile_specialties");
    jdbcTemplate.update("DELETE FROM expert_profiles");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        """
        INSERT INTO users
          (id, role, account_status, is_completed, nickname, email, created_at, updated_at)
        VALUES
          (?, 'EXPERT', 'ACTIVE', TRUE, '전문가', 'expert@example.com', NOW(6), NOW(6)),
          (?, 'GUARDIAN', 'ACTIVE', TRUE, '보호자', 'guardian@example.com', NOW(6), NOW(6)),
          (?, 'EXPERT', 'ACTIVE', TRUE, '검증 전문가', 'verified@example.com', NOW(6), NOW(6))
        """,
        EXPERT_USER_ID,
        GUARDIAN_USER_ID,
        VERIFIED_EXPERT_USER_ID);
    jdbcTemplate.update(
        """
        INSERT INTO expert_profiles
          (id, user_id, display_name, organization, position_title, career_years,
           target_age_min, target_age_max, introduction, is_consultation_available,
           verification_status, workplace, created_at, updated_at)
        VALUES (?, ?, '마음숲 전문가', '마음숲 센터', '상담사', 8, 5, 13,
                '검증된 공개 소개', TRUE, 'VERIFIED', '대전', NOW(6), NOW(6))
        """,
        VERIFIED_EXPERT_PROFILE_ID,
        VERIFIED_EXPERT_USER_ID);
    jdbcTemplate.update(
        """
        INSERT INTO expert_profile_specialties
          (expert_profile_id, specialty_code, specialty_name, display_order, created_at)
        VALUES (?, 'CHILD_ART', '아동 미술', 0, NOW(6))
        """,
        VERIFIED_EXPERT_PROFILE_ID);
    jdbcTemplate.update(
        """
        INSERT INTO expert_follows (guardian_user_id, expert_profile_id, created_at)
        VALUES (?, ?, NOW(6))
        """,
        GUARDIAN_USER_ID,
        VERIFIED_EXPERT_PROFILE_ID);
  }

  @AfterEach
  void clearAuthentication() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void createsPendingProfileAndSpecialtiesForExpert() throws Exception {
    authenticate(EXPERT_USER_ID);

    mockMvc
        .perform(
            post("/api/v1/experts/me/profile")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validRequest()))
        .andExpect(status().isCreated())
        .andExpect(
            header()
                .string("Location", org.hamcrest.Matchers.matchesPattern("/api/v1/experts/\\d+")))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.expertId").isNumber())
        .andExpect(jsonPath("$.data.displayName").value("마음숲 상담사"))
        .andExpect(jsonPath("$.data.specialties[0]").value("CHILD_ART"))
        .andExpect(jsonPath("$.data.specialties[1]").value("PARENT_COUNSELING"))
        .andExpect(jsonPath("$.data.targetAgeMin").value(4))
        .andExpect(jsonPath("$.data.targetAgeMax").value(12))
        .andExpect(jsonPath("$.data.verificationStatus").value("PENDING"))
        .andExpect(jsonPath("$.data.followerCount").value(0))
        .andExpect(jsonPath("$.data.followedByMe").value(false));

    var profile =
        jdbcTemplate.queryForMap(
            """
            SELECT user_id, display_name, organization, position_title, career_years,
                   target_age_min, target_age_max, introduction, is_consultation_available,
                   verification_status, workplace
              FROM expert_profiles
             WHERE user_id = ?
            """,
            EXPERT_USER_ID);
    assertThat(profile)
        .containsEntry("user_id", EXPERT_USER_ID)
        .containsEntry("display_name", "마음숲 상담사")
        .containsEntry("career_years", 6)
        .containsEntry("target_age_min", 4)
        .containsEntry("target_age_max", 12)
        .containsEntry("verification_status", "PENDING");
    assertThat(
            jdbcTemplate.queryForList(
                """
                SELECT specialty_code
                  FROM expert_profile_specialties
                 WHERE expert_profile_id = (
                   SELECT id FROM expert_profiles WHERE user_id = ?
                 )
                 ORDER BY display_order
                """,
                String.class,
                EXPERT_USER_ID))
        .containsExactly("CHILD_ART", "PARENT_COUNSELING");
  }

  @Test
  void rejectsDuplicateProfileForSameUser() throws Exception {
    authenticate(EXPERT_USER_ID);
    mockMvc
        .perform(
            post("/api/v1/experts/me/profile")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validRequest()))
        .andExpect(status().isCreated());

    mockMvc
        .perform(
            post("/api/v1/experts/me/profile")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validRequest()))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("EXPERT_PROFILE_ALREADY_EXISTS"));
  }

  @Test
  void rejectsGuardianRole() throws Exception {
    authenticate(GUARDIAN_USER_ID);

    mockMvc
        .perform(
            post("/api/v1/experts/me/profile")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validRequest()))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("AUTH_403_002"));
  }

  @Test
  void rejectsInvalidAgeRangeAndDuplicateSpecialties() throws Exception {
    authenticate(EXPERT_USER_ID);
    String invalid =
        validRequest()
            .replace("\"targetAgeMin\": 4", "\"targetAgeMin\": 13")
            .replace("\"CHILD_ART\", \"PARENT_COUNSELING\"", "\"CHILD_ART\", \"CHILD_ART\"");

    mockMvc
        .perform(
            post("/api/v1/experts/me/profile")
                .contentType(MediaType.APPLICATION_JSON)
                .content(invalid))
        .andExpect(status().isBadRequest());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM expert_profiles WHERE user_id = ?",
                Integer.class,
                EXPERT_USER_ID))
        .isZero();
  }

  @Test
  void listsVerifiedProfilesWithFiltersAndCurrentGuardianFollowState() throws Exception {
    authenticate(GUARDIAN_USER_ID);

    mockMvc
        .perform(
            get("/api/v1/experts")
                .param("specialty", "child_art")
                .param("consultationAvailable", "true")
                .param("keyword", "마음숲")
                .param("page", "0")
                .param("size", "10"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(jsonPath("$.data.content[0].expertId").value(VERIFIED_EXPERT_PROFILE_ID))
        .andExpect(jsonPath("$.data.content[0].specialties[0]").value("CHILD_ART"))
        .andExpect(jsonPath("$.data.content[0].followerCount").value(1))
        .andExpect(jsonPath("$.data.content[0].followedByMe").value(true));
  }

  @Test
  void returnsVerifiedProfileDetail() throws Exception {
    authenticate(EXPERT_USER_ID);

    mockMvc
        .perform(get("/api/v1/experts/{expertId}", VERIFIED_EXPERT_PROFILE_ID))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.expertId").value(VERIFIED_EXPERT_PROFILE_ID))
        .andExpect(jsonPath("$.data.displayName").value("마음숲 전문가"))
        .andExpect(jsonPath("$.data.followerCount").value(1))
        .andExpect(jsonPath("$.data.followedByMe").value(false));
  }

  private void authenticate(long userId) {
    AuthenticatedUser principal = new AuthenticatedUser(userId);
    SecurityContextHolder.getContext()
        .setAuthentication(
            new UsernamePasswordAuthenticationToken(principal, null, java.util.List.of()));
  }

  private String validRequest() {
    return """
        {
          "displayName": "마음숲 상담사",
          "organization": "마음숲 아동상담센터",
          "positionTitle": "상담사",
          "careerYears": 6,
          "specialties": ["CHILD_ART", "PARENT_COUNSELING"],
          "targetAgeMin": 4,
          "targetAgeMax": 12,
          "introduction": "아동의 표현을 존중하며 상담합니다.",
          "consultationAvailable": true,
          "workplace": "대전광역시"
        }
        """;
  }
}
