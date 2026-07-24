package com.ssafy.b209.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@AutoConfigureMockMvc
class DrawingSnapshotUploadIntegrationTest extends IntegrationTestSupport {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final byte[] PNG =
      new byte[] {(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01};
  private static final Path STORAGE_ROOT = createStorageRoot();

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @DynamicPropertySource
  static void storageProperties(DynamicPropertyRegistry registry) {
    registry.add("app.storage.image.root", () -> STORAGE_ROOT.toString());
  }

  @BeforeEach
  void setUp() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(GUARDIAN_USER_ID), null, List.of()));
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'snapshot-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (1, 'child-one', '2020-07-21', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(guardian_user_id, child_id, relationship_type) VALUES (?, 1, 'MOTHER')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) "
            + "VALUES (1, 'FREE_DRAWING', 'Free Drawing', 'GENERAL', 'BOTH', 3, 12, TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, started_at) "
            + "VALUES (10, 1, 1, 'CANVAS', 'IN_PROGRESS', 'DRAWING', UTC_TIMESTAMP(6))");
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void storesFileAndMetadataAndRejectsDuplicateVersion() throws Exception {
    mockMvc
        .perform(uploadRequest())
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", org.hamcrest.Matchers.endsWith("/snapshots/1")))
        .andExpect(jsonPath("$.data.drawingSessionId").value(10))
        .andExpect(jsonPath("$.data.assetType").value("INTERMEDIATE"))
        .andExpect(jsonPath("$.data.storageKey").doesNotExist());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM drawing_assets WHERE drawing_session_id = 10", Integer.class))
        .isEqualTo(1);
    String storageKey =
        jdbcTemplate.queryForObject(
            "SELECT storage_key FROM drawing_assets WHERE drawing_session_id = 10", String.class);
    assertThat(storageKey).isNotNull();
    assertThat(STORAGE_ROOT.resolve(storageKey)).exists();

    mockMvc
        .perform(uploadRequest())
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("DRAWING_409_005"));
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM drawing_assets WHERE drawing_session_id = 10", Integer.class))
        .isEqualTo(1);
  }

  private org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder
      uploadRequest() {
    MockMultipartFile file = new MockMultipartFile("file", "drawing.png", "image/png", PNG);
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {"assetType":"INTERMEDIATE","assetVersion":1,"capturedAt":"2026-07-22T09:30:00+09:00"}
            """
                .getBytes());
    return multipart("/api/v1/drawing-sessions/{id}/snapshots", 10L).file(file).file(metadata);
  }

  private static Path createStorageRoot() {
    try {
      return Files.createTempDirectory("drawing-snapshot-integration-");
    } catch (IOException exception) {
      throw new IllegalStateException("통합 테스트 Storage Root를 생성할 수 없습니다.", exception);
    }
  }
}
