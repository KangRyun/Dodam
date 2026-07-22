package com.ssafy.b209.analysis;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.reset;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.analysis.dto.BoundingBoxResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisModelResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClient;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClientException;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class DrawingAnalysisIntegrationTest {

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_analysis")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @MockitoBean private DrawingAnalysisClient drawingAnalysisClient;

  @BeforeEach
  void setUp() {
    jdbcTemplate.update("DELETE FROM analysis_detected_objects");
    jdbcTemplate.update("DELETE FROM analyses");
    jdbcTemplate.update("DELETE FROM drawing_assets");
    jdbcTemplate.update("DELETE FROM drawing_sessions");
    jdbcTemplate.update("DELETE FROM drawing_types");
    jdbcTemplate.update("DELETE FROM children");
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (1, 'analysis-child', '2020-07-21', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')");
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
            + "1024, REPEAT('a', 64), UTC_TIMESTAMP(6))");
  }

  @Test
  void storesAnalysisAndDetectionsAndRejectsDuplicateRequest() throws Exception {
    given(drawingAnalysisClient.analyze(any()))
        .willAnswer(
            invocation -> {
              DrawingAnalysisRequest request = invocation.getArgument(0);
              return successResponse(request.requestId());
            });

    mockMvc
        .perform(request())
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

    mockMvc
        .perform(request())
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("ANALYSIS_409_002"));
  }

  @Test
  void preservesFailedRowAndAllowsRetry() throws Exception {
    given(drawingAnalysisClient.analyze(any()))
        .willThrow(new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.TIMEOUT));

    mockMvc
        .perform(request())
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
              DrawingAnalysisRequest request = invocation.getArgument(0);
              return successResponse(request.requestId());
            });
    mockMvc.perform(request()).andExpect(status().isCreated());

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

  private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder request() {
    return post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10)
        .contentType(MediaType.APPLICATION_JSON)
        .content("{\"drawingAssetId\":20,\"analysisType\":\"OBJECT_DETECTION\"}");
  }

  private DrawingAnalysisResponse successResponse(String requestId) {
    return new DrawingAnalysisResponse(
        requestId,
        DrawingAnalysisStatus.SUCCEEDED,
        new DrawingAnalysisModelResponse("mock-drawing-detector", "1.0"),
        List.of(
            detection("HOUSE", "0.95", "120", "80", "640", "520"),
            detection("TREE", "0.91", "820", "120", "380", "700")),
        null,
        Instant.parse("2026-07-22T05:00:01Z"));
  }

  private DrawingDetectionResponse detection(
      String label, String confidence, String x, String y, String width, String height) {
    return new DrawingDetectionResponse(
        label,
        new BigDecimal(confidence),
        new BoundingBoxResponse(
            new BigDecimal(x), new BigDecimal(y), new BigDecimal(width), new BigDecimal(height)));
  }
}
