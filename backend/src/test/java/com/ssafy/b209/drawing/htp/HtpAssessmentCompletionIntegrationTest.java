package com.ssafy.b209.drawing.htp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.nio.charset.StandardCharsets;
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
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.RequestBuilder;

/**
 * 실제 MySQL에서 HTP 종합 완료 접수의 게이트와 사진 업로드 단계 완료를 검증한다.
 *
 * <p>객체 탐지 실패는 완료를 막지 않고 제외 입력으로 남는지, 완료를 막는 사유마다 서로 다른 오류 코드가 나오는지, 업로드 원본이 그 단계의 최종 그림으로 인정되는지를
 * 확인한다. 업로드 세션은 최종 그림을 다시 저장하지 않으므로 리포트 재생성까지 업로드 원본으로 이어지는지도 함께 확인한다.
 */
@AutoConfigureMockMvc
class HtpAssessmentCompletionIntegrationTest extends IntegrationTestSupport {

  private static final long GUARDIAN_ID = 41L;
  private static final long CHILD_ID = 209L;
  private static final long HTP_TYPE_ID = 209L;
  private static final long ASSESSMENT_ID = 2200L;
  private static final long HOUSE_SESSION_ID = 2100L;
  private static final long TREE_SESSION_ID = 2101L;
  private static final long PERSON_SESSION_ID = 2102L;
  private static final long HOUSE_ASSET_ID = 2500L;
  private static final long TREE_ASSET_ID = 2501L;
  private static final long PERSON_ASSET_ID = 2502L;
  private static final long FAILED_ANALYSIS_ID = 2600L;
  private static final long FAILED_REPORT_ID = 2700L;
  private static final String COMPLETION_KEY = "htp-complete-integration-0001";
  private static final String REGENERATION_KEY = "htp-regenerate-integration-0001";
  private static final String LIMITATIONS_TEXT = "이 리포트는 진단이 아닙니다.";
  private static final String MISSING_DETECTION_REASON = "OBJECT_DETECTION_UNAVAILABLE";

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(GUARDIAN_ID), null, List.of()));
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'htp-guardian', 'ACTIVE')",
        GUARDIAN_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, 'htp-child', '2019-07-30', 'PRESCHOOL', 'COMPLETED', 'ACTIVE')",
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(guardian_user_id, child_id, relationship_type) VALUES (?, ?, 'MOTHER')",
        GUARDIAN_ID,
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) "
            + "VALUES (?, 'HTP', '집·나무·사람 그림', 'ASSESSMENT', 'GUARDIAN', 4, 12, TRUE, 20)",
        HTP_TYPE_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void acceptsCompletionWhenEveryStageObjectDetectionFailed() throws Exception {
    seedThreeCanvasStagesWithFailedObjectDetection();

    mockMvc
        .perform(completionRequest(COMPLETION_KEY))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.status").value("ANALYZING"))
        .andExpect(jsonPath("$.data.reportStatus").value("GENERATING"))
        .andExpect(jsonPath("$.data.subjectsWithoutObjectDetection.length()").value(3));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analysis_unused_inputs WHERE excluded_reason_code = ?",
                Integer.class,
                MISSING_DETECTION_REASON))
        .isEqualTo(3);
    assertThat(
            jdbcTemplate.queryForList(
                "SELECT input_name FROM analysis_unused_inputs "
                    + "WHERE excluded_reason_code = ? ORDER BY unused_input_id",
                String.class,
                MISSING_DETECTION_REASON))
        .containsExactly("HOUSE", "TREE", "PERSON");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT status FROM htp_assessments WHERE id = ?", String.class, ASSESSMENT_ID))
        .isEqualTo("COMPLETED");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT report_status FROM reports WHERE drawing_session_id = ?",
                String.class,
                PERSON_SESSION_ID))
        .isEqualTo("COMPLETED");
  }

  @Test
  void recordsOnlyTheStageWithoutUsableObjectDetection() throws Exception {
    seedThreeCanvasStagesWithFailedObjectDetection();
    jdbcTemplate.update(
        "UPDATE analyses SET analysis_status = 'PARTIAL_SUCCESS', error_code = NULL "
            + "WHERE drawing_session_id IN (?, ?)",
        HOUSE_SESSION_ID,
        TREE_SESSION_ID);

    mockMvc
        .perform(completionRequest(COMPLETION_KEY))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.subjectsWithoutObjectDetection.length()").value(1))
        .andExpect(jsonPath("$.data.subjectsWithoutObjectDetection[0]").value("PERSON"));

    assertThat(
            jdbcTemplate.queryForList(
                "SELECT input_name FROM analysis_unused_inputs WHERE excluded_reason_code = ?",
                String.class,
                MISSING_DETECTION_REASON))
        .containsExactly("PERSON");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT source_id FROM analysis_unused_inputs WHERE excluded_reason_code = ?",
                Long.class,
                MISSING_DETECTION_REASON))
        .isEqualTo(PERSON_SESSION_ID);
  }

  @Test
  void rejectsCompletionWithAStageDrawingCodeWhenAStageSessionIsNotCompleted() throws Exception {
    seedThreeCanvasStagesWithFailedObjectDetection();
    jdbcTemplate.update(
        "UPDATE drawing_sessions SET session_status = 'IN_PROGRESS', current_stage = 'REFLECTION', "
            + "completed_at = NULL WHERE id = ?",
        PERSON_SESSION_ID);

    mockMvc
        .perform(completionRequest(COMPLETION_KEY))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("HTP_409_008"));

    assertThat(reportCount()).isZero();
  }

  @Test
  void rejectsCompletionWithAFinalImageCodeWhenAStageHasNoFinalImage() throws Exception {
    seedThreeCanvasStagesWithFailedObjectDetection();
    jdbcTemplate.update("DELETE FROM drawing_assets WHERE id = ?", PERSON_ASSET_ID);

    mockMvc
        .perform(completionRequest(COMPLETION_KEY))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("HTP_409_009"));

    assertThat(reportCount()).isZero();
  }

  @Test
  void rejectsCompletionWithAConversationCodeWhenAStageConversationIsNotCompleted()
      throws Exception {
    seedThreeCanvasStagesWithFailedObjectDetection();
    jdbcTemplate.update(
        "UPDATE conversation_sessions SET conversation_status = 'CONVERSING', completed_at = NULL "
            + "WHERE drawing_session_id = ?",
        PERSON_SESSION_ID);

    mockMvc
        .perform(completionRequest(COMPLETION_KEY))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("HTP_409_010"));

    assertThat(reportCount()).isZero();
  }

  @Test
  void acceptsCompletionWhenEveryStageUploadedItsPhotoInsteadOfDrawingIt() throws Exception {
    seedAssessment(3);
    seedUploadStage(HOUSE_SESSION_ID, HOUSE_ASSET_ID, 1, "HOUSE", "COMPLETED", "COMPLETED");
    seedUploadStage(TREE_SESSION_ID, TREE_ASSET_ID, 2, "TREE", "COMPLETED", "COMPLETED");
    seedUploadStage(PERSON_SESSION_ID, PERSON_ASSET_ID, 3, "PERSON", "COMPLETED", "COMPLETED");
    seedCompletedConversation(HOUSE_SESSION_ID);
    seedCompletedConversation(TREE_SESSION_ID);
    seedCompletedConversation(PERSON_SESSION_ID);

    mockMvc
        .perform(completionRequest(COMPLETION_KEY))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.status").value("ANALYZING"))
        .andExpect(jsonPath("$.data.subjectsWithoutObjectDetection.length()").value(3));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT drawing_asset_id FROM analyses "
                    + "WHERE analysis_task_type = 'ACTIVITY_REPORT'",
                Long.class))
        .isEqualTo(PERSON_ASSET_ID);
    assertThat(reportCount()).isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT report_status FROM reports WHERE drawing_session_id = ?",
                String.class,
                PERSON_SESSION_ID))
        .isEqualTo("COMPLETED");
  }

  /**
   * 사진 업로드 세션의 실패 리포트를 업로드 원본으로 재생성한다.
   *
   * <p>HTP 종합 활동은 새 {@code Idempotency-Key}로 완료를 다시 접수하는 경로로 재시도하므로(계약 7장) 여기서는 단계에 연결되지 않은 업로드 세션
   * 하나로 리포트 재생성 경로만 확인한다. 확인 대상은 {@code FINAL} Asset이 없어도 {@code UPLOADED} 원본이 재생성 입력으로 인정되는지다.
   */
  @Test
  void regeneratesAnUploadReportFromTheUploadedPhotoWithoutRequiringAFinalImage() throws Exception {
    seedUploadSession(PERSON_SESSION_ID, PERSON_ASSET_ID, "PERSON", "FAILED", "REPORTING");
    seedCompletedConversation(PERSON_SESSION_ID);
    seedFailedUploadReport();

    mockMvc
        .perform(
            post("/api/v1/reports/{reportId}/regenerate", FAILED_REPORT_ID)
                .header("Idempotency-Key", REGENERATION_KEY))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.reportVersion").value(2))
        .andExpect(jsonPath("$.data.drawingSessionId").value(PERSON_SESSION_ID));

    assertThat(reportCount()).isEqualTo(2);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT drawing_asset_id FROM analyses WHERE idempotency_key = ?",
                Long.class,
                REGENERATION_KEY))
        .isEqualTo(PERSON_ASSET_ID);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT report_status FROM reports WHERE drawing_session_id = ? "
                    + "AND report_version = 2",
                String.class,
                PERSON_SESSION_ID))
        .isEqualTo("COMPLETED");
  }

  @Test
  void completesAnUploadStageUsingTheUploadedPhotoAsTheAnalysisSource() throws Exception {
    seedAssessment(1);
    seedUploadStage(HOUSE_SESSION_ID, HOUSE_ASSET_ID, 1, "HOUSE", "IN_PROGRESS", "DRAWING");

    mockMvc
        .perform(uploadStageCompletionRequest("htp-upload-stage-complete-0001"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.finalAssetId").value(HOUSE_ASSET_ID))
        .andExpect(jsonPath("$.data.currentStage").value("CONVERSING"))
        .andExpect(jsonPath("$.data.nextAction").value("SELECT_EMOTION"));

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT analysis_type, analysis_task_type, analysis_status, trigger_reason "
                    + "FROM analyses WHERE drawing_asset_id = ?",
                HOUSE_ASSET_ID))
        .containsEntry("analysis_type", "FINAL")
        .containsEntry("analysis_task_type", "OBJECT_DETECTION")
        .containsEntry("analysis_status", "PARTIAL_SUCCESS")
        .containsEntry("trigger_reason", "DRAWING_COMPLETE");
  }

  @Test
  void requiresReflectionBetweenConversationEndAndNextStep() throws Exception {
    seedAssessment(1);
    seedSession(HOUSE_SESSION_ID, "CANVAS", "IN_PROGRESS", "REFLECTION");
    seedStep(HOUSE_SESSION_ID, 1, "HOUSE");
    seedCompletedConversation(HOUSE_SESSION_ID);

    mockMvc
        .perform(nextStepRequest("htp-next-without-reflection-0001"))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("HTP_409_011"));

    mockMvc
        .perform(
            put("/api/v1/drawing-sessions/{drawingSessionId}/reflection", HOUSE_SESSION_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "title": null,
                      "selectedEmotions": ["HAPPY"],
                      "expressedEmotionText": null,
                      "skipped": false
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.selectedEmotions[0]").value("HAPPY"));

    mockMvc
        .perform(nextStepRequest("htp-next-after-reflection-0001"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.currentStep.stepOrder").value(2))
        .andExpect(jsonPath("$.data.currentStep.drawingSubject").value("TREE"));
  }

  private void seedThreeCanvasStagesWithFailedObjectDetection() {
    seedAssessment(3);
    seedCompletedCanvasStage(HOUSE_SESSION_ID, HOUSE_ASSET_ID, 1, "HOUSE");
    seedCompletedCanvasStage(TREE_SESSION_ID, TREE_ASSET_ID, 2, "TREE");
    seedCompletedCanvasStage(PERSON_SESSION_ID, PERSON_ASSET_ID, 3, "PERSON");
  }

  private void seedCompletedCanvasStage(
      long sessionId, long assetId, int stepOrder, String subject) {
    seedSession(sessionId, "CANVAS", "COMPLETED", "COMPLETED");
    seedAsset(assetId, sessionId, "FINAL", "final-" + subject + ".png", "image/png", null);
    seedStep(sessionId, stepOrder, subject);
    seedCompletedConversation(sessionId);
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(drawing_session_id, drawing_asset_id, analysis_type, analysis_task_type, "
            + "idempotency_key, analysis_status, trigger_reason, error_code, requested_at) "
            + "VALUES (?, ?, 'FINAL', 'OBJECT_DETECTION', ?, 'FAILED', 'DRAWING_COMPLETE', "
            + "'TIMEOUT', UTC_TIMESTAMP(6))",
        sessionId,
        assetId,
        "htp-detection-" + sessionId);
  }

  private void seedUploadStage(
      long sessionId,
      long assetId,
      int stepOrder,
      String subject,
      String sessionStatus,
      String currentStage) {
    seedUploadSession(sessionId, assetId, subject, sessionStatus, currentStage);
    seedStep(sessionId, stepOrder, subject);
  }

  private void seedUploadSession(
      long sessionId, long assetId, String subject, String sessionStatus, String currentStage) {
    seedSession(sessionId, "UPLOAD", sessionStatus, currentStage);
    seedAsset(
        assetId,
        sessionId,
        "UPLOADED",
        "uploaded-" + subject + ".jpg",
        "image/jpeg",
        "htp-upload-" + sessionId);
  }

  private void seedSession(
      long sessionId, String inputMethod, String sessionStatus, String currentStage) {
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, completed_at) "
            + "VALUES (?, ?, ?, ?, ?, ?, UTC_TIMESTAMP(6), "
            + "CASE WHEN ? = 'COMPLETED' THEN UTC_TIMESTAMP(6) ELSE NULL END)",
        sessionId,
        CHILD_ID,
        HTP_TYPE_ID,
        inputMethod,
        sessionStatus,
        currentStage,
        sessionStatus);
  }

  private void seedAsset(
      long assetId,
      long sessionId,
      String assetType,
      String fileName,
      String mimeType,
      String uploadIdempotencyKey) {
    jdbcTemplate.update(
        "INSERT INTO drawing_assets "
            + "(id, drawing_session_id, asset_type, asset_version, storage_key, mime_type, "
            + "file_size_bytes, width_px, height_px, checksum_sha256, upload_idempotency_key, "
            + "captured_at) "
            + "VALUES (?, ?, ?, 1, ?, ?, 2048, 1440, 1080, REPEAT('a', 64), ?, UTC_TIMESTAMP(6))",
        assetId,
        sessionId,
        assetType,
        "htp/" + sessionId + "/" + fileName,
        mimeType,
        uploadIdempotencyKey);
  }

  private void seedFailedUploadReport() {
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(id, drawing_session_id, drawing_asset_id, analysis_type, analysis_task_type, "
            + "idempotency_key, analysis_status, trigger_reason, error_code, requested_at) "
            + "VALUES (?, ?, ?, 'FINAL', 'ACTIVITY_REPORT', ?, 'FAILED', 'ACTIVITY_COMPLETE', "
            + "'OBSERVATION_GENERATION_FAILED', UTC_TIMESTAMP(6))",
        FAILED_ANALYSIS_ID,
        PERSON_SESSION_ID,
        PERSON_ASSET_ID,
        COMPLETION_KEY);
    jdbcTemplate.update(
        "INSERT INTO reports "
            + "(id, drawing_session_id, analysis_id, report_version, report_status, "
            + "limitations_text, failure_reason, failed_at) "
            + "VALUES (?, ?, ?, 1, 'FAILED', ?, 'OBSERVATION_GENERATION_FAILED', UTC_TIMESTAMP(6))",
        FAILED_REPORT_ID,
        PERSON_SESSION_ID,
        FAILED_ANALYSIS_ID,
        LIMITATIONS_TEXT);
  }

  private void seedCompletedConversation(long sessionId) {
    jdbcTemplate.update(
        "INSERT INTO conversation_sessions "
            + "(drawing_session_id, conversation_status, difficulty_snapshot, max_question_count, "
            + "question_count, started_at, completed_at) "
            + "VALUES (?, 'COMPLETED', 'PRESCHOOL', 2, 2, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))",
        sessionId);
  }

  private void seedAssessment(int currentStepOrder) {
    jdbcTemplate.update(
        "INSERT INTO htp_assessments "
            + "(id, child_id, drawing_type_id, status, current_step_order, expires_at, created_at, "
            + "idempotency_key) "
            + "VALUES (?, ?, ?, 'IN_PROGRESS', ?, "
            + "DATE_ADD(UTC_TIMESTAMP(6), INTERVAL 12 HOUR), UTC_TIMESTAMP(6), "
            + "'htp-start-integration-0001')",
        ASSESSMENT_ID,
        CHILD_ID,
        HTP_TYPE_ID,
        currentStepOrder);
  }

  private void seedStep(long sessionId, int stepOrder, String subject) {
    jdbcTemplate.update(
        "INSERT INTO htp_assessment_steps "
            + "(htp_assessment_id, step_order, drawing_subject, drawing_session_id, retry_count, "
            + "transition_idempotency_key, created_at) "
            + "VALUES (?, ?, ?, ?, 0, ?, UTC_TIMESTAMP(6))",
        ASSESSMENT_ID,
        stepOrder,
        subject,
        sessionId,
        "htp-step-" + sessionId);
  }

  private RequestBuilder completionRequest(String idempotencyKey) {
    return post("/api/v1/htp-assessments/{assessmentId}/complete", ASSESSMENT_ID)
        .header("Idempotency-Key", idempotencyKey);
  }

  private RequestBuilder nextStepRequest(String idempotencyKey) {
    return post("/api/v1/htp-assessments/{assessmentId}/steps/next", ASSESSMENT_ID)
        .header("Idempotency-Key", idempotencyKey)
        .contentType(MediaType.APPLICATION_JSON)
        .content("{\"inputMethod\":\"CANVAS\"}");
  }

  private RequestBuilder uploadStageCompletionRequest(String idempotencyKey) {
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {
              "sourceAssetId": %d,
              "drawingDurationMs": 120000,
              "clientCompletedAt": "2026-07-30T10:00:00+09:00"
            }
            """
                .formatted(HOUSE_ASSET_ID)
                .getBytes(StandardCharsets.UTF_8));
    return multipart(
            "/api/v1/drawing-sessions/{drawingSessionId}/drawing-complete", HOUSE_SESSION_ID)
        .file(metadata)
        .header("Idempotency-Key", idempotencyKey);
  }

  private int reportCount() {
    return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM reports", Integer.class);
  }
}
