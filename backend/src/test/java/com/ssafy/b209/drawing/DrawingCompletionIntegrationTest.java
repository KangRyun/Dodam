package com.ssafy.b209.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClient;
import com.ssafy.b209.infrastructure.ai.observation.AiObservationClientException;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;

/** MySQL에서 그림 활동 완료 접수의 분석·리포트·세션 전환과 DB 멱등성을 함께 검증한다. */
@AutoConfigureMockMvc
class DrawingCompletionIntegrationTest extends IntegrationTestSupport {

  private static final long GUARDIAN_ID = 41L;
  private static final long SESSION_ID = 1430L;

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @MockitoSpyBean private AiObservationClient observationClient;

  @BeforeEach
  void setUp() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(GUARDIAN_ID), null, List.of()));
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'completion-guardian', 'ACTIVE')",
        GUARDIAN_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (143, 'completion-child', '2020-07-23', 'PRESCHOOL', 'COMPLETED', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(guardian_user_id, child_id, relationship_type) VALUES (?, 143, 'MOTHER')",
        GUARDIAN_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "VALUES (143, 'COMPLETION_TEST', 'Completion Test', 'GENERAL', 'BOTH', TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, started_at) "
            + "VALUES (?, 143, 143, 'CANVAS', 'IN_PROGRESS', 'REFLECTION', UTC_TIMESTAMP(6))",
        SESSION_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_assets "
            + "(id, drawing_session_id, asset_type, asset_version, storage_key, mime_type, "
            + "file_size_bytes, checksum_sha256, captured_at) "
            + "VALUES (1430, ?, 'FINAL', 1, 'completion/final.png', 'image/png', "
            + "8, REPEAT('c', 64), UTC_TIMESTAMP(6))",
        SESSION_ID);
    jdbcTemplate.update(
        "INSERT INTO conversation_sessions "
            + "(drawing_session_id, conversation_status, difficulty_snapshot, "
            + "max_question_count, question_count, started_at, completed_at) "
            + "VALUES (?, 'COMPLETED', 'PRESCHOOL', 5, 3, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))",
        SESSION_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void storesCompletionGeneratesMockReportAndStaysIdempotent() throws Exception {
    // 접수 시점에 활동은 이미 COMPLETED 다. 리포트만 GENERATING 으로 따로 간다(P0-2).
    mockMvc
        .perform(completionRequest("completion-key-143"))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.currentStage").value("COMPLETED"))
        .andExpect(jsonPath("$.data.analysisStatus").value("PENDING"))
        .andExpect(jsonPath("$.data.reportStatus").value("GENERATING"));

    // AFTER_COMMIT 동기 Mock 생성이 완료되어 분석·리포트와 활동 세션이 함께 완료 전이된다.
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT analysis_status FROM analyses WHERE drawing_session_id = ?",
                String.class,
                SESSION_ID))
        .isEqualTo("SUCCESS");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT report_status FROM reports WHERE drawing_session_id = ?",
                String.class,
                SESSION_ID))
        .isEqualTo("COMPLETED");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT analysis_task_type FROM analyses WHERE drawing_session_id = ?",
                String.class,
                SESSION_ID))
        .isEqualTo("ACTIVITY_REPORT");
    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT session_status, current_stage, completed_at "
                    + "FROM drawing_sessions WHERE id = ?",
                SESSION_ID))
        .containsEntry("session_status", "COMPLETED")
        .containsEntry("current_stage", "COMPLETED")
        .doesNotContainEntry("completed_at", null);

    // 정규화 저장이 실제로 채워졌는지 확인한다.
    assertThat(count("analysis_observation_results")).isGreaterThanOrEqualTo(1);
    assertThat(count("analysis_conversation_summaries")).isGreaterThanOrEqualTo(1);
    assertThat(count("report_activity_summaries")).isEqualTo(1);

    // 같은 키 재요청은 새 행 없이 멱등하게 처리되고, 진행된 현재 상태를 반환한다.
    mockMvc
        .perform(completionRequest("completion-key-143"))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.analysisStatus").value("SUCCESS"))
        .andExpect(jsonPath("$.data.reportStatus").value("COMPLETED"));
    assertThat(count("analyses")).isEqualTo(1);
    assertThat(count("reports")).isEqualTo(1);
    assertThat(count("analysis_observation_results")).isEqualTo(1);
    assertThat(count("report_activity_summaries")).isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT current_stage FROM drawing_sessions WHERE id = ?",
                String.class,
                SESSION_ID))
        .isEqualTo("COMPLETED");

    // 다른 키 요청은 세션이 이미 COMPLETED라 409로 거절되고 행 수는 그대로다.
    mockMvc.perform(completionRequest("another-completion-key")).andExpect(status().isConflict());
    assertThat(count("analyses")).isEqualTo(1);
    assertThat(count("reports")).isEqualTo(1);
  }

  /**
   * 리포트가 실패해도 아이가 한 활동은 완료로 남는다 (P0-2).
   *
   * <p>예전에는 이 자리에서 그림 세션이 {@code FAILED} 로 내려가, 아이 화면에 "활동을 마무리하지 못했어요"가 떴다(2026-08-08 실측). 그림을
   * 그렸고 마음을 골랐고 대화를 마친 활동이, 그 뒤에 도는 LLM 호출 하나 때문에 실패가 됐던 것이다.
   *
   * <p>{@code TIMEOUT} 은 상대편이 잠깐 흔들린 것이라 리포트는 {@code FAILED_RETRYABLE} 로 남아 재시도 대기열이 집어 간다.
   */
  @Test
  void keepsActivityCompletedAndQueuesRetryWhenReportGenerationTimesOut() throws Exception {
    doThrow(new AiObservationClientException(AiObservationClientException.Type.TIMEOUT))
        .when(observationClient)
        .generate(any());

    mockMvc
        .perform(completionRequest("failure-key-335"))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.currentStage").value("COMPLETED"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT analysis_status FROM analyses WHERE drawing_session_id = ?",
                String.class,
                SESSION_ID))
        .isEqualTo("FAILED");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT report_status FROM reports WHERE drawing_session_id = ?",
                String.class,
                SESSION_ID))
        .isEqualTo("FAILED_RETRYABLE");
    Map<String, Object> session =
        jdbcTemplate.queryForMap(
            "SELECT session_status, current_stage, completed_at "
                + "FROM drawing_sessions WHERE id = ?",
            SESSION_ID);
    assertThat(session)
        .containsEntry("session_status", "COMPLETED")
        .containsEntry("current_stage", "COMPLETED");
    assertThat(session.get("completed_at")).isNotNull();
  }

  /** 근거·계약 위반은 다시 해도 같은 자리에서 멈추므로 재시도 대상이 아니다 (P0-2). */
  @Test
  void marksReportFinalWhenResponseIsInvalid() throws Exception {
    doThrow(new AiObservationClientException(AiObservationClientException.Type.INVALID_RESPONSE))
        .when(observationClient)
        .generate(any());

    mockMvc
        .perform(completionRequest("invalid-key-335"))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.currentStage").value("COMPLETED"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT report_status FROM reports WHERE drawing_session_id = ?",
                String.class,
                SESSION_ID))
        .isEqualTo("FAILED_FINAL");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT session_status FROM drawing_sessions WHERE id = ?",
                String.class,
                SESSION_ID))
        .isEqualTo("COMPLETED");
  }

  @Test
  void rejectsCompletionWithoutReportAndKeepsReflectionState() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/complete", SESSION_ID)
                .header("Idempotency-Key", "reportless-completion-key")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"conversationSkipped\":false,\"requestReport\":false}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("DRAWING_400_012"));

    assertThat(count("analyses")).isZero();
    assertThat(count("reports")).isZero();
    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT session_status, current_stage FROM drawing_sessions WHERE id = ?",
                SESSION_ID))
        .containsEntry("session_status", "IN_PROGRESS")
        .containsEntry("current_stage", "REFLECTION");
  }

  private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder
      completionRequest(String idempotencyKey) {
    return post("/api/v1/drawing-sessions/{drawingSessionId}/complete", SESSION_ID)
        .header("Idempotency-Key", idempotencyKey)
        .contentType(MediaType.APPLICATION_JSON)
        .content("{\"conversationSkipped\":false,\"requestReport\":true}");
  }

  private int count(String tableName) {
    return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM " + tableName, Integer.class);
  }
}
