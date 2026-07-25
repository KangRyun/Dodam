package com.ssafy.b209.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 활동 기록·스냅샷·분석 이력·그림 초안의 조회 계열 endpoint를 실 MySQL과 실 파일 저장소로 관통 검증하는 통합 테스트다.
 *
 * <p>기존 통합 테스트는 쓰기 경로(세션 생성·스냅샷 업로드·분석 요청)만 덮고 있어, 보호자 화면이 실제로 호출하는 목록·이력 조회와 초안 저장·조회는 단위 테스트만
 * 있었다. 이 클래스는 소유권 404 통일, 정렬·페이징 화이트리스트, 최신순 정렬, 초안 버전 증가와 역행 거부를 함께 검증한다.
 *
 * <p>인증은 다른 단면 통합 테스트와 같이 검증된 {@link AuthenticatedUser} Principal을 SecurityContext에 넣어 재현하고, 조회 대상
 * 데이터는 jdbc로 구성한다. 초안 저장만 실제 multipart 요청으로 수행해 이미지 저장 경계까지 실행한다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class DrawingActivityQueryIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long OTHER_GUARDIAN_USER_ID = 42L;
  private static final Long CHILD_ID = 1L;
  private static final Long OTHER_CHILD_ID = 2L;
  private static final long DRAWING_SESSION_ID = 10L;
  private static final long COMPLETED_SESSION_ID = 11L;
  private static final long DELETED_SESSION_ID = 12L;
  private static final long OTHER_CHILD_SESSION_ID = 13L;
  private static final byte[] PNG =
      new byte[] {(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01};
  private static final Path STORAGE_ROOT = createStorageRoot();

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_activity_query")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @DynamicPropertySource
  static void storageProperties(DynamicPropertyRegistry registry) {
    registry.add("app.storage.image.root", STORAGE_ROOT::toString);
  }

  @BeforeEach
  void setUp() {
    authenticate(GUARDIAN_USER_ID);
    jdbcTemplate.update("DELETE FROM storage_deletion_jobs");
    jdbcTemplate.update("DELETE FROM reports");
    jdbcTemplate.update("DELETE FROM analysis_detected_objects");
    jdbcTemplate.update("DELETE FROM analyses");
    jdbcTemplate.update("DELETE FROM drawing_session_emotions");
    jdbcTemplate.update("DELETE FROM drawing_assets");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.update("DELETE FROM guardian_child_relations");
    jdbcTemplate.update("DELETE FROM child_response_modes");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update("DELETE FROM drawing_types");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) VALUES "
            + "(?, 'GUARDIAN', 'activity-guardian', 'ACTIVE'), "
            + "(?, 'GUARDIAN', 'other-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, '별이', '2020-03-02', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE'), "
            + "(?, '남의아이', '2019-05-06', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')",
        CHILD_ID,
        OTHER_CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations (guardian_user_id, child_id, relationship_type) "
            + "VALUES (?, ?, 'MOTHER'), (?, ?, 'MOTHER')",
        GUARDIAN_USER_ID,
        CHILD_ID,
        OTHER_GUARDIAN_USER_ID,
        OTHER_CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) VALUES "
            + "(1, 'FREE_DRAWING', 'Free Drawing', 'GENERAL', 'BOTH', 3, 12, TRUE, 1), "
            + "(2, 'FAMILY_DRAWING', 'Family Drawing', 'ASSESSMENT', 'BOTH', 3, 12, TRUE, 2)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, completed_at, deleted_at) VALUES "
            + "(?, ?, 1, 'CANVAS', 'IN_PROGRESS', 'DRAWING', '2026-07-20 01:00:00', NULL, NULL), "
            + "(?, ?, 2, 'CANVAS', 'COMPLETED', 'COMPLETED', '2026-07-22 01:00:00', "
            + "'2026-07-22 02:00:00', NULL), "
            + "(?, ?, 1, 'CANVAS', 'DELETED', 'DRAWING', '2026-07-23 01:00:00', NULL, "
            + "'2026-07-23 02:00:00'), "
            + "(?, ?, 1, 'CANVAS', 'IN_PROGRESS', 'DRAWING', '2026-07-21 01:00:00', NULL, NULL)",
        DRAWING_SESSION_ID,
        CHILD_ID,
        COMPLETED_SESSION_ID,
        CHILD_ID,
        DELETED_SESSION_ID,
        CHILD_ID,
        OTHER_CHILD_SESSION_ID,
        OTHER_CHILD_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  // ---------------------------------------------------------------- 154 활동 기록 목록

  @Test
  void listsChildActivitiesNewestFirstAndExcludesDeletedOnes() throws Exception {
    mockMvc
        .perform(get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(2))
        .andExpect(jsonPath("$.data.page").value(0))
        .andExpect(jsonPath("$.data.size").value(20))
        .andExpect(jsonPath("$.data.first").value(true))
        .andExpect(jsonPath("$.data.last").value(true))
        .andExpect(jsonPath("$.data.content[0].drawingSessionId").value((int) COMPLETED_SESSION_ID))
        .andExpect(jsonPath("$.data.content[0].drawingType.code").value("FAMILY_DRAWING"))
        .andExpect(jsonPath("$.data.content[0].sessionStatus").value("COMPLETED"))
        .andExpect(jsonPath("$.data.content[0].currentStage").value("COMPLETED"))
        .andExpect(jsonPath("$.data.content[0].completedAt").value("2026-07-22T02:00:00Z"))
        .andExpect(jsonPath("$.data.content[0].selectedEmotions").isEmpty())
        .andExpect(jsonPath("$.data.content[1].drawingSessionId").value((int) DRAWING_SESSION_ID))
        .andExpect(jsonPath("$.data.content[1].startedAt").value("2026-07-20T01:00:00Z"))
        .andExpect(jsonPath("$.data.content[1].completedAt").doesNotExist());
  }

  @Test
  void exposesLatestAnalysisAndReportStateForActivity() throws Exception {
    insertAsset(200, COMPLETED_SESSION_ID, "FINAL", 1);
    insertAnalysis(300, COMPLETED_SESSION_ID, 200, "SUCCESS", "2026-07-22 01:30:00");
    jdbcTemplate.update(
        "INSERT INTO reports "
            + "(id, drawing_session_id, analysis_id, report_version, report_status, "
            + "limitations_text) VALUES (400, ?, 300, 1, 'COMPLETED', '참고용 자료입니다.')",
        COMPLETED_SESSION_ID);

    mockMvc
        .perform(get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content[0].analysisStatus").value("SUCCEEDED"))
        .andExpect(jsonPath("$.data.content[0].reportId").value(400))
        .andExpect(jsonPath("$.data.content[0].reportStatus").value("COMPLETED"));
  }

  @Test
  void filtersActivitiesByTypeStatusAndStartDateRange() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID)
                .param("drawingTypeCode", "FAMILY_DRAWING"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(
            jsonPath("$.data.content[0].drawingSessionId").value((int) COMPLETED_SESSION_ID));

    mockMvc
        .perform(
            get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID)
                .param("sessionStatus", "IN_PROGRESS"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(jsonPath("$.data.content[0].drawingSessionId").value((int) DRAWING_SESSION_ID));

    mockMvc
        .perform(
            get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID)
                .param("from", "2026-07-21")
                .param("to", "2026-07-22"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(
            jsonPath("$.data.content[0].drawingSessionId").value((int) COMPLETED_SESSION_ID));
  }

  @Test
  void paginatesActivityHistoryWithAscendingSort() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID)
                .param("size", "1")
                .param("page", "0")
                .param("sort", "startedAt,asc"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content.length()").value(1))
        .andExpect(jsonPath("$.data.content[0].drawingSessionId").value((int) DRAWING_SESSION_ID))
        .andExpect(jsonPath("$.data.totalPages").value(2))
        .andExpect(jsonPath("$.data.hasNext").value(true))
        .andExpect(jsonPath("$.data.last").value(false));

    mockMvc
        .perform(
            get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID)
                .param("size", "1")
                .param("page", "1")
                .param("sort", "startedAt,asc"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content[0].drawingSessionId").value((int) COMPLETED_SESSION_ID))
        .andExpect(jsonPath("$.data.first").value(false))
        .andExpect(jsonPath("$.data.hasNext").value(false));
  }

  @Test
  void rejectsActivityQueryOutsideAllowedSortAndPageRange() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID)
                .param("sort", "title,desc"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    mockMvc
        .perform(get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID).param("size", "101"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    mockMvc
        .perform(get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID).param("page", "-1"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    mockMvc
        .perform(
            get("/api/v1/children/{childId}/drawing-sessions", CHILD_ID)
                .param("from", "2026-07-25")
                .param("to", "2026-07-20"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void hidesOtherGuardiansChildActivitiesAsNotFound() throws Exception {
    mockMvc
        .perform(get("/api/v1/children/{childId}/drawing-sessions", OTHER_CHILD_ID))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("CHILD_404_001"));
  }

  // ---------------------------------------------------------------- 338 스냅샷 목록

  @Test
  void listsSnapshotsNewestFirstWithoutInternalStorageKey() throws Exception {
    insertAsset(201, DRAWING_SESSION_ID, "DRAFT", 1);
    insertAsset(202, DRAWING_SESSION_ID, "INTERMEDIATE", 1);
    insertAsset(203, DRAWING_SESSION_ID, "FINAL", 1);

    String body =
        mockMvc
            .perform(get("/api/v1/drawing-sessions/{id}/snapshots", DRAWING_SESSION_ID))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.length()").value(3))
            .andExpect(jsonPath("$.data[0].drawingAssetId").value(203))
            .andExpect(jsonPath("$.data[0].assetType").value("FINAL"))
            .andExpect(jsonPath("$.data[0].mimeType").value("image/png"))
            .andExpect(jsonPath("$.data[0].fileSizeBytes").value(10))
            .andExpect(jsonPath("$.data[2].drawingAssetId").value(201))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    assertThat(body).doesNotContain("storageKey").doesNotContain("drawing-sessions/10/");
  }

  @Test
  void returnsEmptySnapshotListWhenSessionHasNoAssets() throws Exception {
    mockMvc
        .perform(get("/api/v1/drawing-sessions/{id}/snapshots", DRAWING_SESSION_ID))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data").isEmpty());
  }

  @Test
  void hidesSnapshotsOfInaccessibleSessionAsNotFound() throws Exception {
    insertAsset(204, OTHER_CHILD_SESSION_ID, "FINAL", 1);

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{id}/snapshots", OTHER_CHILD_SESSION_ID))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DRAWING_404_003"));
  }

  // ---------------------------------------------------------------- 341 분석 이력 목록

  @Test
  void listsAnalysesNewestFirstWithContractStatus() throws Exception {
    insertAsset(205, DRAWING_SESSION_ID, "FINAL", 1);
    insertAnalysis(301, DRAWING_SESSION_ID, 205, "SUCCESS", "2026-07-20 03:00:00");
    insertAnalysis(302, DRAWING_SESSION_ID, 205, "FAILED", null);

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{id}/analyses", DRAWING_SESSION_ID))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.length()").value(2))
        .andExpect(jsonPath("$.data[0].drawingAnalysisId").value(302))
        .andExpect(jsonPath("$.data[0].drawingAssetId").value(205))
        .andExpect(jsonPath("$.data[0].scope").value("FINAL"))
        .andExpect(jsonPath("$.data[0].taskType").value("OBJECT_DETECTION"))
        .andExpect(jsonPath("$.data[0].state").value("FAILED"))
        .andExpect(jsonPath("$.data[0].completedAt").doesNotExist())
        .andExpect(jsonPath("$.data[1].drawingAnalysisId").value(301))
        .andExpect(jsonPath("$.data[1].state").value("SUCCESS"))
        .andExpect(jsonPath("$.data[1].completedAt").value("2026-07-20T03:00:00Z"));
  }

  @Test
  void hidesAnalysesOfInaccessibleSessionAsNotFound() throws Exception {
    mockMvc
        .perform(get("/api/v1/drawing-sessions/{id}/analyses", OTHER_CHILD_SESSION_ID))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DRAWING_404_003"));
  }

  // ---------------------------------------------------------------- 279 그림 초안 저장·조회

  @Test
  void savesDraftVersionsAndReadsTheLatestOne() throws Exception {
    mockMvc
        .perform(saveDraft(DRAWING_SESSION_ID, 10))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.drawingSessionId").value((int) DRAWING_SESSION_ID))
        .andExpect(jsonPath("$.data.assetType").value("DRAFT"))
        .andExpect(jsonPath("$.data.assetVersion").value(1))
        .andExpect(jsonPath("$.data.lastEventSequence").value(10))
        .andExpect(jsonPath("$.data.finalSnapshot").value(false));

    mockMvc
        .perform(saveDraft(DRAWING_SESSION_ID, 20))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.assetVersion").value(2))
        .andExpect(jsonPath("$.data.lastEventSequence").value(20));

    String body =
        mockMvc
            .perform(get("/api/v1/drawing-sessions/{id}/draft", DRAWING_SESSION_ID))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.assetVersion").value(2))
            .andExpect(jsonPath("$.data.lastEventSequence").value(20))
            .andExpect(jsonPath("$.data.contentType").value("image/png"))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    assertThat(body).doesNotContain("storageKey").doesNotContain(STORAGE_ROOT.toString());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM drawing_assets WHERE drawing_session_id = ? "
                    + "AND asset_type = 'DRAFT'",
                Integer.class,
                DRAWING_SESSION_ID))
        .isEqualTo(2);
  }

  @Test
  void rejectsDraftWithSequenceOlderThanTheStoredOne() throws Exception {
    mockMvc.perform(saveDraft(DRAWING_SESSION_ID, 20)).andExpect(status().isOk());

    mockMvc
        .perform(saveDraft(DRAWING_SESSION_ID, 5))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("DRAWING_409_010"));
  }

  @Test
  void rejectsDraftWhenSessionIsNoLongerUploadable() throws Exception {
    mockMvc
        .perform(saveDraft(COMPLETED_SESSION_ID, 10))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("DRAWING_409_008"));
  }

  @Test
  void returnsNotFoundWhenNoDraftWasSaved() throws Exception {
    mockMvc
        .perform(get("/api/v1/drawing-sessions/{id}/draft", DRAWING_SESSION_ID))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DRAWING_404_004"));
  }

  @Test
  void hidesDraftOfInaccessibleSessionAsNotFound() throws Exception {
    mockMvc
        .perform(get("/api/v1/drawing-sessions/{id}/draft", OTHER_CHILD_SESSION_ID))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DRAWING_404_003"));

    mockMvc
        .perform(saveDraft(OTHER_CHILD_SESSION_ID, 10))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DRAWING_404_003"));
  }

  // ---------------------------------------------------------------- 요청·fixture 도우미

  private MockMultipartHttpServletRequestBuilder saveDraft(long drawingSessionId, long sequence) {
    MockMultipartHttpServletRequestBuilder builder =
        multipart("/api/v1/drawing-sessions/{id}/draft", drawingSessionId);
    builder.with(
        request -> {
          request.setMethod(HttpMethod.PUT.name());
          return request;
        });
    return (MockMultipartHttpServletRequestBuilder)
        builder
            .file(new MockMultipartFile("preview", "preview.png", "image/png", PNG))
            .file(
                new MockMultipartFile(
                    "canvasState",
                    "canvasState.json",
                    MediaType.APPLICATION_JSON_VALUE,
                    ("{\"lastEventSequence\":"
                            + sequence
                            + ",\"clientSavedAt\":\"2026-07-20T11:30:00+09:00\"}")
                        .getBytes(StandardCharsets.UTF_8)));
  }

  private void insertAsset(long id, long drawingSessionId, String assetType, int version) {
    jdbcTemplate.update(
        "INSERT INTO drawing_assets "
            + "(id, drawing_session_id, asset_type, asset_version, storage_key, mime_type, "
            + "file_size_bytes, checksum_sha256, captured_at) "
            + "VALUES (?, ?, ?, ?, ?, 'image/png', 10, REPEAT('a', 64), '2026-07-20 02:00:00')",
        id,
        drawingSessionId,
        assetType,
        version,
        "drawing-sessions/" + drawingSessionId + "/asset-" + id + ".png");
  }

  private void insertAnalysis(
      long id, long drawingSessionId, long drawingAssetId, String status, String completedAt) {
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(id, drawing_session_id, drawing_asset_id, analysis_type, analysis_task_type, "
            + "idempotency_key, analysis_status, requested_at, completed_at) "
            + "VALUES (?, ?, ?, 'FINAL', 'OBJECT_DETECTION', ?, ?, ?, ?)",
        id,
        drawingSessionId,
        drawingAssetId,
        "analysis-key-" + id,
        status,
        "2026-07-20 0" + (id % 7) + ":00:00",
        completedAt);
  }

  private void authenticate(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }

  private static Path createStorageRoot() {
    try {
      return Files.createTempDirectory("activity-query-integration-");
    } catch (IOException exception) {
      throw new IllegalStateException("통합 테스트 Storage Root를 생성할 수 없습니다.", exception);
    }
  }
}
