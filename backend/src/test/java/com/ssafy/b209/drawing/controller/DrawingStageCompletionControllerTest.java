package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.CompleteDrawingStageRequest;
import com.ssafy.b209.drawing.dto.response.CompleteDrawingStageResponse;
import com.ssafy.b209.drawing.dto.response.DrawingStageAnalysisResponse;
import com.ssafy.b209.drawing.service.DrawingStageCompletionService;
import com.ssafy.b209.storage.image.StoreImageCommand;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingStageCompletionController.class)
@org.springframework.context.annotation.Import(
    com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingStageCompletionControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingStageCompletionService service;

  @Test
  void completesTheDrawingStageFromMultipartParts() throws Exception {
    given(
            service.complete(
                eq(10L),
                eq("drawing-complete-key"),
                any(StoreImageCommand.class),
                any(CompleteDrawingStageRequest.class)))
        .willReturn(response());

    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/drawing-complete", 10L)
                .file(image())
                .file(metadata())
                .header("Idempotency-Key", "drawing-complete-key"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.drawingSessionId").value(10))
        .andExpect(jsonPath("$.data.finalAssetId").value(20))
        .andExpect(jsonPath("$.data.currentStage").value("CONVERSING"))
        .andExpect(jsonPath("$.data.analysis.analysisType").value("OBJECT_DETECTION"))
        .andExpect(jsonPath("$.data.analysis.status").value("SUCCEEDED"))
        .andExpect(jsonPath("$.data.nextAction").value("SELECT_EMOTION"));

    verify(service)
        .complete(
            eq(10L),
            eq("drawing-complete-key"),
            any(StoreImageCommand.class),
            any(CompleteDrawingStageRequest.class));
  }

  @Test
  void delegatesMissingHeaderAndFileForDomainValidation() throws Exception {
    given(service.complete(eq(10L), eq(null), eq(null), any(CompleteDrawingStageRequest.class)))
        .willReturn(response());

    mockMvc
        .perform(multipart("/api/v1/drawing-sessions/{id}/drawing-complete", 10L).file(metadata()))
        .andExpect(status().isOk());

    verify(service).complete(eq(10L), eq(null), eq(null), any(CompleteDrawingStageRequest.class));
  }

  @Test
  void rejectsInvalidMetadataBeforeCallingTheService() throws Exception {
    MockMultipartFile invalidMetadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {"lastEventSequence":-1,"drawingDurationMs":0}
            """
                .getBytes(StandardCharsets.UTF_8));

    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/drawing-complete", 10L)
                .file(image())
                .file(invalidMetadata)
                .header("Idempotency-Key", "drawing-complete-key"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  private MockMultipartFile image() {
    return new MockMultipartFile("finalImage", "drawing.png", "image/png", new byte[] {1, 2, 3});
  }

  private MockMultipartFile metadata() {
    return new MockMultipartFile(
        "metadata",
        "metadata.json",
        MediaType.APPLICATION_JSON_VALUE,
        """
        {
          "lastEventSequence":15,
          "drawingDurationMs":120000,
          "clientCompletedAt":"2026-07-25T19:30:00+09:00"
        }
        """
            .getBytes(StandardCharsets.UTF_8));
  }

  private CompleteDrawingStageResponse response() {
    return new CompleteDrawingStageResponse(
        10L,
        20L,
        DrawingSessionStatus.IN_PROGRESS,
        DrawingStage.CONVERSING,
        new DrawingStageAnalysisResponse(
            30L, DrawingAnalysisType.OBJECT_DETECTION, DrawingAnalysisStatus.SUCCEEDED),
        "SELECT_EMOTION");
  }
}
