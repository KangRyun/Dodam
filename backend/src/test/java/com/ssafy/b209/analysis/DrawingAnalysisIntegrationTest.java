package com.ssafy.b209.analysis;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClient;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClientException;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.math.BigDecimal;
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
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@AutoConfigureMockMvc
class DrawingAnalysisIntegrationTest extends IntegrationTestSupport {

  private static final Long GUARDIAN_USER_ID = 41L;

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @MockitoBean private DrawingAnalysisClient drawingAnalysisClient;

  @BeforeEach
  void setUp() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(GUARDIAN_USER_ID), null, List.of()));
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'analysis-guardian', 'ACTIVE')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (1, 'analysis-child', '2020-07-21', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO guardian_child_relations "
            + "(guardian_user_id, child_id, relationship_type) VALUES (?, 1, 'MOTHER')",
        GUARDIAN_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) "
            + "VALUES (1, 'ANALYSIS_DRAWING', 'Analysis Drawing', 'GENERAL', 'BOTH', "
            + "3, 12, TRUE, 1)");
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, started_at) "
            + "VALUES (10, 1, 1, 'CANVAS', 'IN_PROGRESS', 'DRAWING', UTC_TIMESTAMP(6))");
    jdbcTemplate.update(
        "INSERT INTO drawing_assets "
            + "(id, drawing_session_id, asset_type, asset_version, storage_key, mime_type, "
            + "file_size_bytes, checksum_sha256, captured_at) "
            + "VALUES (20, 10, 'FINAL', 1, '2026/07/22/final.png', 'image/png', "
            + "1024, REPEAT('a', 64), UTC_TIMESTAMP(6)), "
            + "(21, 10, 'DRAFT', 1, '2026/07/22/draft.png', 'image/png', "
            + "768, REPEAT('b', 64), UTC_TIMESTAMP(6))");
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void storesAnalysisAndDetectionsAndRejectsDuplicateRequest() throws Exception {
    given(drawingAnalysisClient.analyze(any()))
        .willAnswer(
            invocation -> {
              com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand request =
                  invocation.getArgument(0);
              return successResponse(request.analysisId());
            });

    mockMvc
        .perform(request(20L, "OBJECT_DETECTION"))
        .andExpect(status().isCreated())
        .andExpect(header().exists("Location"))
        .andExpect(jsonPath("$.data.status").value("SUCCEEDED"))
        .andExpect(jsonPath("$.data.detections.length()").value(2));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT analysis_status FROM analyses WHERE drawing_asset_id = 20", String.class))
        .isEqualTo("SUCCESS");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT analysis_type FROM analyses WHERE drawing_asset_id = 20", String.class))
        .isEqualTo("FINAL");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT analysis_task_type FROM analyses WHERE drawing_asset_id = 20",
                String.class))
        .isEqualTo("OBJECT_DETECTION");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analysis_detected_objects", Integer.class))
        .isEqualTo(2);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT coordinate_space FROM analysis_detected_objects "
                    + "ORDER BY detection_order LIMIT 1",
                String.class))
        .isEqualTo("NORMALIZED");
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analysis_model_components", Integer.class))
        .isEqualTo(4);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT image_width_px FROM analysis_visual_features", Integer.class))
        .isEqualTo(1200);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT pressure_available FROM analysis_behavior_features", Boolean.class))
        .isFalse();
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analysis_conversation_summaries", Integer.class))
        .isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analysis_observation_items", Integer.class))
        .isEqualTo(2);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analysis_evidence_references", Integer.class))
        .isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analysis_evidence_reference_authors", Integer.class))
        .isEqualTo(1);
    assertThat(
            jdbcTemplate.queryForObject("SELECT warning_code FROM analysis_warnings", String.class))
        .isEqualTo("TEST_WARNING");

    mockMvc
        .perform(request(20L, "OBJECT_DETECTION"))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("ANALYSIS_409_002"));
  }

  @Test
  void storesDraftObjectDetectionAsIntermediateAnalysis() throws Exception {
    given(drawingAnalysisClient.analyze(any()))
        .willAnswer(
            invocation -> {
              com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand request =
                  invocation.getArgument(0);
              return successResponse(request.analysisId());
            });

    mockMvc
        .perform(request(21L, "OBJECT_DETECTION"))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.drawingAssetId").value(21));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT analysis_type FROM analyses WHERE drawing_asset_id = 21", String.class))
        .isEqualTo("INTERMEDIATE");
  }

  @Test
  void rejectsActivityReportFromPublicRequestWithoutCallingAnalysisClient() throws Exception {
    mockMvc
        .perform(request(21L, "ACTIVITY_REPORT"))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("ANALYSIS_409_001"));

    verifyNoInteractions(drawingAnalysisClient);
  }

  @Test
  void preservesFailedRowAndAllowsRetry() throws Exception {
    given(drawingAnalysisClient.analyze(any()))
        .willThrow(new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.TIMEOUT));

    mockMvc
        .perform(request(20L, "OBJECT_DETECTION"))
        .andExpect(status().isBadGateway())
        .andExpect(jsonPath("$.code").value("ANALYSIS_502_001"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT analysis_status FROM analyses WHERE drawing_asset_id = 20", String.class))
        .isEqualTo("FAILED");

    reset(drawingAnalysisClient);
    given(drawingAnalysisClient.analyze(any()))
        .willAnswer(
            invocation -> {
              com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand request =
                  invocation.getArgument(0);
              return successResponse(request.analysisId());
            });
    mockMvc.perform(request(20L, "OBJECT_DETECTION")).andExpect(status().isCreated());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analyses WHERE drawing_asset_id = 20", Integer.class))
        .isEqualTo(2);
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM analyses WHERE drawing_asset_id = 20 "
                    + "AND analysis_status = 'FAILED'",
                Integer.class))
        .isEqualTo(1);
  }

  @Test
  void retriesAFailedAnalysisWithTheLatestMatchingAssetAndLinksItsSource() throws Exception {
    given(drawingAnalysisClient.analyze(any()))
        .willThrow(new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.TIMEOUT));
    mockMvc.perform(request(21L, "OBJECT_DETECTION")).andExpect(status().isBadGateway());
    Long failedAnalysisId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM analyses WHERE drawing_asset_id = 21", Long.class);
    jdbcTemplate.update(
        "INSERT INTO drawing_assets "
            + "(id, drawing_session_id, asset_type, asset_version, storage_key, mime_type, "
            + "file_size_bytes, checksum_sha256, captured_at) "
            + "VALUES (22, 10, 'DRAFT', 2, '2026/07/22/draft-v2.png', 'image/png', "
            + "1200, REPEAT('c', 64), UTC_TIMESTAMP(6))");

    reset(drawingAnalysisClient);
    given(drawingAnalysisClient.analyze(any()))
        .willAnswer(
            invocation -> {
              com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand request =
                  invocation.getArgument(0);
              return successResponse(request.analysisId());
            });

    mockMvc
        .perform(
            post("/api/v1/analyses/{analysisId}/retry", failedAnalysisId)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"reason\":\"USER_REQUEST\",\"useLatestInputs\":true}"))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.drawingAssetId").value(22))
        .andExpect(jsonPath("$.data.status").value("SUCCEEDED"));

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT retry_of_analysis_id, trigger_reason, drawing_asset_id "
                    + "FROM analyses WHERE retry_of_analysis_id = ?",
                failedAnalysisId))
        .containsEntry("retry_of_analysis_id", failedAnalysisId)
        .containsEntry("trigger_reason", "RETRY")
        .containsEntry("drawing_asset_id", 22L);
  }

  @Test
  void queriesStoredSuccessWithoutCallingAnalysisClientAgain() throws Exception {
    given(drawingAnalysisClient.analyze(any()))
        .willAnswer(
            invocation -> {
              com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand request =
                  invocation.getArgument(0);
              return successResponse(request.analysisId());
            });
    mockMvc.perform(request(20L, "OBJECT_DETECTION")).andExpect(status().isCreated());
    Long analysisId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM analyses WHERE drawing_asset_id = 20", Long.class);
    reset(drawingAnalysisClient);

    mockMvc
        .perform(
            get(
                "/api/v1/drawing-sessions/{drawingSessionId}/analyses/{drawingAnalysisId}",
                10,
                analysisId))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.status").value("SUCCEEDED"))
        .andExpect(jsonPath("$.data.detections[0].label").value("HOUSE"))
        .andExpect(jsonPath("$.data.detections[1].label").value("TREE"))
        .andExpect(jsonPath("$.data.failure").isEmpty());

    verifyNoInteractions(drawingAnalysisClient);
  }

  @Test
  void queriesStoredFailureAsHttpOkWithoutCallingAnalysisClientAgain() throws Exception {
    given(drawingAnalysisClient.analyze(any()))
        .willThrow(new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.TIMEOUT));
    mockMvc.perform(request(20L, "OBJECT_DETECTION")).andExpect(status().isBadGateway());
    Long analysisId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM analyses WHERE drawing_asset_id = 20", Long.class);
    reset(drawingAnalysisClient);

    mockMvc
        .perform(
            get(
                "/api/v1/drawing-sessions/{drawingSessionId}/analyses/{drawingAnalysisId}",
                10,
                analysisId))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.status").value("FAILED"))
        .andExpect(jsonPath("$.data.detections").isEmpty())
        .andExpect(jsonPath("$.data.failure.code").value("AI_ANALYSIS_FAILED"))
        .andExpect(jsonPath("$.data.failure.message").value("그림 분석 처리에 실패했습니다."));

    verifyNoInteractions(drawingAnalysisClient);
  }

  private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder request(
      long drawingAssetId, String analysisType) {
    return post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10)
        .contentType(MediaType.APPLICATION_JSON)
        .content(
            """
            {"drawingAssetId":%d,"analysisType":"%s"}
            """
                .formatted(drawingAssetId, analysisType));
  }

  private com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
      successResponse(Long analysisId) {
    var model =
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.ModelRef(
            "mock-drawing-detector", "1.0");
    var vision =
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.ModelRef(
            "vision-model", "1.0");
    var language =
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.ModelRef(
            "language-model", "1.0");
    java.util.Map<String, Object> visualFeatures = new java.util.LinkedHashMap<>();
    visualFeatures.put("imageWidth", 1200);
    visualFeatures.put("imageHeight", 800);
    visualFeatures.put("occupancyRatio", 0.34);
    visualFeatures.put("strokeThickness", null);
    java.util.Map<String, Object> behaviorFeatures = new java.util.LinkedHashMap<>();
    behaviorFeatures.put("drawingDurationMs", 1000);
    behaviorFeatures.put("pressureAvailable", false);
    behaviorFeatures.put("pressureMean", null);
    return new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse(
        analysisId,
        com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.AnalysisStatus
            .SUCCESS,
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.ModelInfo(
            model, vision, language, "2026.07"),
        List.of(
            detection("HOUSE", "집", "0.95", "0.10", "0.10", "0.40", "0.45", 0),
            detection("TREE", "나무", "0.91", "0.60", "0.15", "0.25", "0.60", 1)),
        visualFeatures,
        behaviorFeatures,
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
            .ConversationSummary("함께 있는 사람을 설명했습니다.", "친구와 있어요", 2, 1, 0, 0),
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
            .ObservationDraft(
            "AI_DRAFT",
            "전문가 검토용 초안",
            List.of("그림의 중심에 인물이 있습니다."),
            List.of("누구와 함께 있나요?"),
            true,
            "진단 결과가 아닙니다."),
        List.of(
            new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
                .EvidenceReference(
                "source-1",
                "테스트 근거",
                List.of("연구자"),
                2026,
                "section",
                "PRACTICE_GUIDELINE",
                "관찰 참고",
                "개별 맥락 검토 필요",
                "2026.07",
                "chunk-hash")),
        List.of(),
        List.of("TEST_WARNING"),
        10L);
  }

  private com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.DetectedObject
      detection(
          String code,
          String name,
          String confidence,
          String x,
          String y,
          String width,
          String height,
          int order) {
    BigDecimal widthValue = new BigDecimal(width);
    BigDecimal heightValue = new BigDecimal(height);
    return new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse
        .DetectedObject(
        code,
        name,
        new BigDecimal(confidence),
        new com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse.BoundingBox(
            new BigDecimal(x), new BigDecimal(y), widthValue, heightValue),
        widthValue.multiply(heightValue),
        order);
  }
}
