package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.CompleteDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingCompletionResponse;
import com.ssafy.b209.drawing.service.DrawingCompletionService;
import com.ssafy.b209.report.domain.ReportStatus;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingCompletionController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingCompletionControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingCompletionService service;

  @Test
  void acceptsCompletionRequestWithPendingAnalysisAndGeneratingReport() throws Exception {
    given(
            service.complete(
                eq(100L), eq("completion-key"), any(CompleteDrawingSessionRequest.class)))
        .willReturn(
            new DrawingCompletionResponse(
                100L,
                DrawingSessionStatus.IN_PROGRESS,
                DrawingStage.COMPLETED,
                701L,
                DrawingAnalysisState.PENDING,
                900L,
                ReportStatus.GENERATING));

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/complete", 100L)
                .header("Idempotency-Key", "completion-key")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"conversationSkipped\":false,\"requestReport\":true}"))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.currentStage").value("COMPLETED"))
        .andExpect(jsonPath("$.data.analysisStatus").value("PENDING"))
        .andExpect(jsonPath("$.data.reportStatus").value("GENERATING"));
  }

  @Test
  void rejectsMissingRequiredBodyFieldBeforeServiceCall() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/{drawingSessionId}/complete", 100L)
                .header("Idempotency-Key", "completion-key")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"conversationSkipped\":false}"))
        .andExpect(status().isBadRequest());

    verifyNoInteractions(service);
  }
}
