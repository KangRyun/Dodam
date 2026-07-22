package com.ssafy.b209.analysis.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.analysis.dto.BoundingBoxResponse;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisModelResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.service.DrawingAnalysisService;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingAnalysisController.class)
@org.springframework.context.annotation.Import(
    com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingAnalysisControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingAnalysisService drawingAnalysisService;

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
}
