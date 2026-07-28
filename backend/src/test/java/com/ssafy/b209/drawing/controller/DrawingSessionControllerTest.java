package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.CreateDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.request.DeleteDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.ActiveDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.CreateDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionAnalysisSummaryResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionAssetSummaryResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionChildSummaryResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionDetailResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeSummaryResponse;
import com.ssafy.b209.drawing.dto.response.LatestDrawingDraftResponse;
import com.ssafy.b209.drawing.dto.response.StrokeBatchResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.service.DrawingSessionDeletionService;
import com.ssafy.b209.drawing.service.DrawingSessionQueryService;
import com.ssafy.b209.drawing.service.DrawingSessionService;
import com.ssafy.b209.drawing.service.StrokeBatchSaveResult;
import com.ssafy.b209.drawing.service.StrokeBatchService;
import com.ssafy.b209.global.exception.BusinessException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest({DrawingSessionController.class, StrokeBatchController.class})
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
  @MockitoBean private DrawingSessionDeletionService drawingSessionDeletionService;
  @MockitoBean private StrokeBatchService strokeBatchService;

  @Test
  void returnsCreatedForANewStrokeBatchAndOkForTheSamePayloadRetry() throws Exception {
    StrokeBatchResponse response =
        new StrokeBatchResponse(15L, 3, 1, 101, Instant.parse("2026-07-21T02:32:10Z"));
    given(strokeBatchService.save(eq(100L), any()))
        .willReturn(new StrokeBatchSaveResult(response, true))
        .willReturn(new StrokeBatchSaveResult(response, false));

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/100/stroke-batches")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validStrokeBatch()))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.batchId").value(15))
        .andExpect(jsonPath("$.data.acceptedEventCount").value(1));

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/100/stroke-batches")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validStrokeBatch()))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"));
  }

  @Test
  void rejectsInvalidStrokeCoordinatesBeforeCallingTheService() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/100/stroke-batches")
                .contentType(MediaType.APPLICATION_JSON)
                .content(validStrokeBatch().replace("\"x\":0.18", "\"x\":1.18")))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsStrokeBatchHttpBodyOverOneMebibyteBeforeDeserialization() throws Exception {
    String valid = validStrokeBatch();
    int paddingLength = 1024 * 1024 + 1 - valid.getBytes(StandardCharsets.UTF_8).length;
    String oversized = valid + " ".repeat(paddingLength);

    mockMvc
        .perform(
            post("/api/v1/drawing-sessions/100/stroke-batches")
                .contentType(MediaType.APPLICATION_JSON)
                .content(oversized))
        .andExpect(status().isPayloadTooLarge())
        .andExpect(jsonPath("$.code").value("DRAWING_413_001"))
        .andExpect(jsonPath("$.message").value("그림 과정 데이터가 1 MiB 제한을 초과했습니다."));

    verifyNoInteractions(strokeBatchService);
  }

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
        .andExpect(
            jsonPath("$.data.latestDraft.previewUrl").value("/api/v1/drawing-assets/200/file"));
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

  @Test
  void returnsDrawingSessionDetailWithoutInternalStorageKey() throws Exception {
    given(drawingSessionQueryService.getDrawingSessionDetail(100L)).willReturn(detailResponse());

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}", 100))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.drawingSessionId").value(100))
        .andExpect(jsonPath("$.data.child.nickname").value("도담"))
        .andExpect(jsonPath("$.data.selectedEmotions[0]").value("HAPPY"))
        .andExpect(jsonPath("$.data.latestAsset.drawingAssetId").value(200))
        .andExpect(jsonPath("$.data.latestAsset.storageKey").doesNotExist())
        .andExpect(jsonPath("$.data.latestAnalysis.drawingAnalysisId").value(300))
        .andExpect(jsonPath("$.data.recoverableDraft").value(true));
  }

  @Test
  void rejectsNonPositiveDrawingSessionId() throws Exception {
    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}", 0))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void returnsNotFoundForInaccessibleDrawingSession() throws Exception {
    given(drawingSessionQueryService.getDrawingSessionDetail(999L))
        .willThrow(new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{drawingSessionId}", 999))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("DRAWING_404_003"));
  }

  @Test
  void deletesDrawingSessionAfterExplicitConfirmation() throws Exception {
    mockMvc
        .perform(
            delete("/api/v1/drawing-sessions/100")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNoContent());

    verify(drawingSessionDeletionService).delete(100L, new DeleteDrawingSessionRequest("DELETE"));
  }

  @Test
  void rejectsDrawingSessionDeletionWithoutConfirmation() throws Exception {
    mockMvc
        .perform(
            delete("/api/v1/drawing-sessions/100")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  private String validStrokeBatch() {
    return """
        {
          "batchSequence": 3,
          "firstEventSequence": 101,
          "lastEventSequence": 101,
          "clientCreatedAt": "2026-07-21T11:32:10.120+09:00",
          "events": [{
            "sequence": 101,
            "eventType": "STROKE",
            "tool": "PEN",
            "color": "#FFCC00",
            "width": 8.0,
            "pressure": null,
            "points": [{"x":0.18,"y":0.42,"t":0},{"x":0.19,"y":0.43,"t":16}]
          }],
          "metrics": {
            "undoCountDelta": 1,
            "redoCountDelta": 0,
            "eraseCountDelta": 2,
            "pauseDurationMsDelta": 3200
          }
        }
        """;
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
        "/api/v1/drawing-assets/200/file");
  }

  private DrawingSessionDetailResponse detailResponse() {
    return new DrawingSessionDetailResponse(
        100L,
        new DrawingSessionChildSummaryResponse(1L, "도담"),
        new DrawingTypeSummaryResponse(2L, "FREE_DRAWING", "자유화"),
        DrawingInputMethod.CANVAS,
        "우리 집",
        List.of(DrawingEmotionCode.HAPPY),
        DrawingSessionStatus.IN_PROGRESS,
        DrawingStage.REFLECTION,
        new DrawingSessionAssetSummaryResponse(
            200L,
            DrawingAssetType.DRAFT,
            3,
            "image/png",
            4096L,
            Instant.parse("2026-07-21T02:35:00Z"),
            Instant.parse("2026-07-21T02:35:01Z")),
        new DrawingSessionAnalysisSummaryResponse(
            300L,
            DrawingAnalysisScope.INTERMEDIATE,
            DrawingAnalysisType.OBJECT_DETECTION,
            DrawingAnalysisState.SUCCESS,
            Instant.parse("2026-07-21T02:35:02Z"),
            Instant.parse("2026-07-21T02:35:03Z")),
        400L,
        null,
        Instant.parse("2026-07-21T02:30:00Z"),
        null,
        true);
  }
}
