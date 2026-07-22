package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.CreateDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.ActiveDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.CreateDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeSummaryResponse;
import com.ssafy.b209.drawing.dto.response.LatestDrawingDraftResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.service.DrawingSessionQueryService;
import com.ssafy.b209.drawing.service.DrawingSessionService;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingSessionController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingSessionControllerTest {

  private static final String KEY = "550e8400-e29b-41d4-a716-446655440000";
  private static final String VALID_REQUEST =
      """
      {
        "childId": 1,
        "drawingTypeId": 2,
        "inputMethod": "CANVAS",
        "clientStartedAt": "2026-07-21T11:30:00+09:00",
        "canvas": {"width": 1920, "height": 1080, "backgroundColor": "#FFFFFF"}
      }
      """;

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingSessionService drawingSessionService;
  @MockitoBean private DrawingSessionQueryService drawingSessionQueryService;

  @Test
  void returnsCreatedResponseAndLocation() throws Exception {
    given(
            drawingSessionService.createDrawingSession(
                eq(KEY), any(CreateDrawingSessionRequest.class)))
        .willReturn(response());

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions")
                .header("Idempotency-Key", KEY)
                .contentType(MediaType.APPLICATION_JSON)
                .content(VALID_REQUEST))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/drawing-sessions/100"))
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.drawingSessionId").value(100))
        .andExpect(jsonPath("$.data.sessionStatus").value("IN_PROGRESS"))
        .andExpect(jsonPath("$.data.currentStage").value("DRAWING"));
  }

  @Test
  void delegatesMissingHeaderToDrawingValidation() throws Exception {
    given(drawingSessionService.createDrawingSession(eq(null), any()))
        .willThrow(new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_REQUIRED));

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions")
                .contentType(MediaType.APPLICATION_JSON)
                .content(VALID_REQUEST))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("DRAWING_400_003"));
  }

  @Test
  void rejectsInvalidRequestBodyBeforeCallingService() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions")
                .header("Idempotency-Key", KEY)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"childId\":0}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void returnsTheActiveSessionAndLatestDraft() throws Exception {
    given(drawingSessionQueryService.getActiveDrawingSession(1L))
        .willReturn(activeResponse(latestDraft()));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/active").queryParam("childId", "1"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.drawingSessionId").value(100))
        .andExpect(jsonPath("$.data.childId").value(1))
        .andExpect(jsonPath("$.data.drawingType.code").value("FREE_DRAWING"))
        .andExpect(jsonPath("$.data.sessionStatus").value("IN_PROGRESS"))
        .andExpect(jsonPath("$.data.currentStage").value("DRAWING"))
        .andExpect(jsonPath("$.data.latestDraft.drawingAssetId").value(200))
        .andExpect(jsonPath("$.data.latestDraft.assetVersion").value(3))
        .andExpect(jsonPath("$.data.latestDraft.lastEventSequence").value(17))
        .andExpect(jsonPath("$.data.latestDraft.previewUrl").isEmpty());
  }

  @Test
  void returnsNullLatestDraftWhenTheActiveSessionHasNoDraft() throws Exception {
    given(drawingSessionQueryService.getActiveDrawingSession(1L)).willReturn(activeResponse(null));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/active").queryParam("childId", "1"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.latestDraft").isEmpty());
  }

  @Test
  void rejectsMissingOrNonPositiveChildId() throws Exception {
    mockMvc.perform(get("/api/v1/drawing-sessions/active")).andExpect(status().isBadRequest());
    mockMvc
        .perform(get("/api/v1/drawing-sessions/active").queryParam("childId", "0"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  private CreateDrawingSessionResponse response() {
    return new CreateDrawingSessionResponse(
        100L,
        1L,
        new DrawingTypeSummaryResponse(2L, "FREE_DRAWING", "자유화"),
        DrawingInputMethod.CANVAS,
        DrawingSessionStatus.IN_PROGRESS,
        DrawingStage.DRAWING,
        true,
        Instant.parse("2026-07-21T02:30:00Z"));
  }

  private ActiveDrawingSessionResponse activeResponse(LatestDrawingDraftResponse latestDraft) {
    return new ActiveDrawingSessionResponse(
        100L,
        1L,
        new DrawingTypeSummaryResponse(2L, "FREE_DRAWING", "자유화"),
        DrawingInputMethod.CANVAS,
        DrawingSessionStatus.IN_PROGRESS,
        DrawingStage.DRAWING,
        Instant.parse("2026-07-21T02:30:00Z"),
        latestDraft);
  }

  private LatestDrawingDraftResponse latestDraft() {
    return new LatestDrawingDraftResponse(
        200L,
        3,
        17L,
        "image/png",
        4096L,
        Instant.parse("2026-07-21T02:35:00Z"),
        Instant.parse("2026-07-21T02:35:01Z"),
        null);
  }
}
