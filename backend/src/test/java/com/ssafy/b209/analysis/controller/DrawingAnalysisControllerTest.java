package com.ssafy.b209.analysis.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.BoundingBoxResponse;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisDetailResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisFailureResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisHistoryResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisModelResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.service.DrawingAnalysisQueryService;
import com.ssafy.b209.analysis.service.DrawingAnalysisService;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest({DrawingAnalysisController.class, DrawingAnalysisRetryController.class})
@org.springframework.context.annotation.Import(
    com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingAnalysisControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingAnalysisService drawingAnalysisService;
  @MockitoBean private DrawingAnalysisQueryService drawingAnalysisQueryService;

  @Test
  void returnsAnalysisHistoryForTheSession() throws Exception {
    given(drawingAnalysisQueryService.getDrawingAnalyses(10L))
        .willReturn(
            List.of(
                new DrawingAnalysisHistoryResponse(
                    30L,
                    20L,
                    DrawingAnalysisScope.FINAL,
                    DrawingAnalysisType.OBJECT_DETECTION,
                    DrawingAnalysisState.SUCCESS,
                    Instant.parse("2026-07-22T05:00:00Z"),
                    Instant.parse("2026-07-22T05:00:01Z"))));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10L))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data[0].drawingAnalysisId").value(30))
        .andExpect(jsonPath("$.data[0].drawingAssetId").value(20))
        .andExpect(jsonPath("$.data[0].state").value("SUCCESS"))
        .andExpect(jsonPath("$.data[0].taskType").value("OBJECT_DETECTION"));
  }

  @Test
  void returnsCreatedResponseAndAnalysisLocation() throws Exception {
    given(drawingAnalysisService.requestAnalysis(eq(10L), any(CreateDrawingAnalysisRequest.class)))
        .willReturn(response());

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10L)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"drawingAssetId\":20,\"analysisType\":\"OBJECT_DETECTION\"}"))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/drawing-sessions/10/analyses/30"))
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.drawingAnalysisId").value(30))
        .andExpect(jsonPath("$.data.requestId").value("550e8400-e29b-41d4-a716-446655440000"))
        .andExpect(jsonPath("$.data.status").value("SUCCEEDED"))
        .andExpect(jsonPath("$.data.model.name").value("mock-drawing-detector"))
        .andExpect(jsonPath("$.data.detections[0].label").value("HOUSE"))
        .andExpect(jsonPath("$.data.storageKey").doesNotExist());
  }

  @Test
  void preservesPauseTriggerReasonAtTheServiceBoundary() throws Exception {
    given(drawingAnalysisService.requestAnalysis(eq(10L), any(CreateDrawingAnalysisRequest.class)))
        .willReturn(response());

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10L)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "drawingAssetId": 20,
                      "analysisType": "OBJECT_DETECTION",
                      "triggerReason": "PAUSE"
                    }
                    """))
        .andExpect(status().isCreated());

    ArgumentCaptor<CreateDrawingAnalysisRequest> requestCaptor =
        ArgumentCaptor.forClass(CreateDrawingAnalysisRequest.class);
    verify(drawingAnalysisService).requestAnalysis(eq(10L), requestCaptor.capture());
    String serialized = new ObjectMapper().writeValueAsString(requestCaptor.getValue());
    Assertions.assertThat(serialized).contains("\"triggerReason\":\"PAUSE\"");
  }

  @Test
  void retriesAFailedAnalysisByItsIdentifier() throws Exception {
    given(drawingAnalysisService.retryAnalysis(eq(30L), any(), eq("analysis-retry-key-0001")))
        .willReturn(response());

    mockMvc
        .perform(
            post("/api/v1/analyses/{analysisId}/retry", 30L)
                .header("Idempotency-Key", "analysis-retry-key-0001")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"reason\":\"USER_REQUEST\",\"useLatestInputs\":true}"))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/drawing-sessions/10/analyses/30"))
        .andExpect(jsonPath("$.data.status").value("SUCCEEDED"));

    verify(drawingAnalysisService).retryAnalysis(eq(30L), any(), eq("analysis-retry-key-0001"));
  }

  @Test
  void rejectsAnInvalidRetryRequest() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/analyses/{analysisId}/retry", 30L)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"useLatestInputs\":true}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsRetryWithoutAnIdempotencyKey() throws Exception {
    given(drawingAnalysisService.retryAnalysis(eq(30L), any(), isNull()))
        .willThrow(
            new BusinessException(
                DrawingAnalysisErrorCode.DRAWING_ANALYSIS_IDEMPOTENCY_KEY_REQUIRED));

    mockMvc
        .perform(
            post("/api/v1/analyses/{analysisId}/retry", 30L)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"reason\":\"USER_REQUEST\",\"useLatestInputs\":true}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("ANALYSIS_400_001"));
  }

  @Test
  void rejectsInvalidPathAndRequestBody() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 0)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"drawingAssetId\":20,\"analysisType\":\"OBJECT_DETECTION\"}"))
        .andExpect(status().isBadRequest());

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"analysisType\":\"OBJECT_DETECTION\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"drawingAssetId\":20,\"analysisType\":\"UNKNOWN\"}"))
        .andExpect(status().isBadRequest());
  }

  @Test
  void rejectsTriggerReasonsThatAreNotExposedByThePublicApi() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "drawingAssetId": 20,
                      "analysisType": "OBJECT_DETECTION",
                      "triggerReason": "INTERVAL"
                    }
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void returnsSafeClientFailureResponse() throws Exception {
    given(drawingAnalysisService.requestAnalysis(eq(10L), any(CreateDrawingAnalysisRequest.class)))
        .willThrow(new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED));

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/analyses", 10)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"drawingAssetId\":20,\"analysisType\":\"OBJECT_DETECTION\"}"))
        .andExpect(status().isBadGateway())
        .andExpect(jsonPath("$.code").value("ANALYSIS_502_001"))
        .andExpect(jsonPath("$.stackTrace").doesNotExist());
  }

  @Test
  void returnsStoredAnalysisResultWithOkResponse() throws Exception {
    given(drawingAnalysisQueryService.getDrawingAnalysis(10L, 30L))
        .willReturn(detailResponse(DrawingAnalysisStatus.SUCCEEDED));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}/analyses/{analysisId}", 10, 30))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.drawingAnalysisId").value(30))
        .andExpect(jsonPath("$.data.status").value("SUCCEEDED"))
        .andExpect(jsonPath("$.data.detections[0].label").value("HOUSE"))
        .andExpect(jsonPath("$.data.failure").isEmpty())
        .andExpect(jsonPath("$.data.storageKey").doesNotExist());
  }

  @Test
  void returnsFailedAnalysisAsHttpOk() throws Exception {
    given(drawingAnalysisQueryService.getDrawingAnalysis(10L, 30L))
        .willReturn(detailResponse(DrawingAnalysisStatus.FAILED));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}/analyses/{analysisId}", 10, 30))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.status").value("FAILED"))
        .andExpect(jsonPath("$.data.detections").isArray())
        .andExpect(jsonPath("$.data.detections").isEmpty())
        .andExpect(jsonPath("$.data.failure.code").value("AI_ANALYSIS_FAILED"));
  }

  @ParameterizedTest
  @EnumSource(
      value = DrawingAnalysisStatus.class,
      names = {"PENDING", "PROCESSING"})
  void returnsInProgressStatusWithEmptyDetections(DrawingAnalysisStatus statusValue)
      throws Exception {
    given(drawingAnalysisQueryService.getDrawingAnalysis(10L, 30L))
        .willReturn(detailResponse(statusValue));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}/analyses/{analysisId}", 10, 30))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.status").value(statusValue.name()))
        .andExpect(jsonPath("$.data.model").isEmpty())
        .andExpect(jsonPath("$.data.detections").isArray())
        .andExpect(jsonPath("$.data.detections").isEmpty())
        .andExpect(jsonPath("$.data.processedAt").isEmpty())
        .andExpect(jsonPath("$.data.failure").isEmpty());
  }

  @Test
  void validatesAnalysisPathAndReturnsSafeNotFound() throws Exception {
    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}/analyses/{analysisId}", 10, 0))
        .andExpect(status().isBadRequest());

    given(drawingAnalysisQueryService.getDrawingAnalysis(10L, 30L))
        .willThrow(new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_FOUND));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}/analyses/{analysisId}", 10, 30))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("ANALYSIS_404_002"))
        .andExpect(jsonPath("$.stackTrace").doesNotExist());
  }

  private CreateDrawingAnalysisResponse response() {
    return new CreateDrawingAnalysisResponse(
        30L,
        10L,
        20L,
        "550e8400-e29b-41d4-a716-446655440000",
        DrawingAnalysisType.OBJECT_DETECTION,
        DrawingAnalysisStatus.SUCCEEDED,
        new DrawingAnalysisModelResponse("mock-drawing-detector", "1.0"),
        List.of(
            new DrawingDetectionResponse(
                "HOUSE",
                new BigDecimal("0.95"),
                new BoundingBoxResponse(
                    new BigDecimal("120"),
                    new BigDecimal("80"),
                    new BigDecimal("640"),
                    new BigDecimal("520")))),
        Instant.parse("2026-07-22T05:00:00Z"),
        Instant.parse("2026-07-22T05:00:01Z"));
  }

  private DrawingAnalysisDetailResponse detailResponse(DrawingAnalysisStatus status) {
    boolean succeeded = status == DrawingAnalysisStatus.SUCCEEDED;
    boolean failed = status == DrawingAnalysisStatus.FAILED;
    return new DrawingAnalysisDetailResponse(
        30L,
        10L,
        20L,
        "550e8400-e29b-41d4-a716-446655440000",
        DrawingAnalysisType.OBJECT_DETECTION,
        status,
        succeeded ? new DrawingAnalysisModelResponse("mock-drawing-detector", "1.0") : null,
        succeeded
            ? List.of(
                new DrawingDetectionResponse(
                    "HOUSE",
                    new BigDecimal("0.95"),
                    new BoundingBoxResponse(
                        new BigDecimal("120"),
                        new BigDecimal("80"),
                        new BigDecimal("640"),
                        new BigDecimal("520"))))
            : List.of(),
        Instant.parse("2026-07-22T05:00:00Z"),
        failed || succeeded ? Instant.parse("2026-07-22T05:00:01Z") : null,
        failed
            ? new DrawingAnalysisFailureResponse("AI_ANALYSIS_FAILED", "그림 분석 처리에 실패했습니다.")
            : null);
  }
}
