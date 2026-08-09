package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.dto.request.SaveDrawingDraftRequest;
import com.ssafy.b209.drawing.dto.response.DrawingCanvasStateResponse;
import com.ssafy.b209.drawing.dto.response.DrawingDraftResponse;
import com.ssafy.b209.drawing.service.DrawingDraftIdempotencyStore;
import com.ssafy.b209.drawing.service.DrawingDraftService;
import com.ssafy.b209.storage.image.ImageStorageProperties;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingDraftController.class)
@org.springframework.context.annotation.Import(
    com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingDraftControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingDraftService drawingDraftService;
  @MockitoBean private DrawingDraftIdempotencyStore idempotencyStore;
  @MockitoBean private CurrentAuthenticatedUserResolver currentUserResolver;
  @MockitoBean private ImageStorageProperties imageStorageProperties;

  @Test
  void replacesCurrentDraftWithPreviewAndCanvasState() throws Exception {
    given(imageStorageProperties.maxSize()).willReturn(10_485_760L);
    given(currentUserResolver.requireUserId()).willReturn(1L);
    given(
            idempotencyStore.execute(
                eq(1L),
                eq(10L),
                eq("draft-key-0001"),
                any(byte[].class),
                any(SaveDrawingDraftRequest.class),
                any()))
        .willReturn(response());

    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/draft", 10L)
                .file(preview())
                .file(canvasState(17, true))
                .header("Idempotency-Key", "draft-key-0001")
                .with(
                    request -> {
                      request.setMethod("PUT");
                      return request;
                    }))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.assetType").value("DRAFT"))
        .andExpect(jsonPath("$.data.assetVersion").value(3))
        .andExpect(jsonPath("$.data.lastEventSequence").value(17))
        .andExpect(jsonPath("$.data.finalSnapshot").value(false))
        .andExpect(jsonPath("$.data.storageKey").doesNotExist())
        .andExpect(jsonPath("$.data.previewUrl").value("/api/v1/drawing-assets/20/file"));
  }

  @Test
  void rejectsMissingPreviewAndInvalidCanvasState() throws Exception {
    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/draft", 10L)
                .file(canvasState(17, true))
                .with(
                    request -> {
                      request.setMethod("PUT");
                      return request;
                    }))
        .andExpect(status().isBadRequest());

    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/draft", 10L)
                .file(preview())
                .file(canvasState(0, false))
                .header("Idempotency-Key", "draft-key-0002")
                .with(
                    request -> {
                      request.setMethod("PUT");
                      return request;
                    }))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void acceptsExplicitZeroEventSequence() throws Exception {
    given(imageStorageProperties.maxSize()).willReturn(10_485_760L);
    given(currentUserResolver.requireUserId()).willReturn(1L);
    given(
            idempotencyStore.execute(
                eq(1L),
                eq(10L),
                eq("draft-key-zero"),
                any(byte[].class),
                any(SaveDrawingDraftRequest.class),
                any()))
        .willReturn(response());

    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/draft", 10L)
                .file(preview())
                .file(canvasState(0, true))
                .header("Idempotency-Key", "draft-key-zero")
                .with(
                    request -> {
                      request.setMethod("PUT");
                      return request;
                    }))
        .andExpect(status().isOk());
  }

  @Test
  void rejectsMissingEventSequence() throws Exception {
    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/draft", 10L)
                .file(preview())
                .file(canvasState("{\"clientSavedAt\":\"2026-07-22T14:30:00+09:00\"}"))
                .header("Idempotency-Key", "draft-key-missing")
                .with(
                    request -> {
                      request.setMethod("PUT");
                      return request;
                    }))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsNegativeEventSequence() throws Exception {
    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/draft", 10L)
                .file(preview())
                .file(canvasState(-1, true))
                .header("Idempotency-Key", "draft-key-negative")
                .with(
                    request -> {
                      request.setMethod("PUT");
                      return request;
                    }))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void returnsLatestDraftMetadata() throws Exception {
    given(drawingDraftService.getLatest(10L)).willReturn(response());

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{id}/draft", 10L))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.drawingAssetId").value(20))
        .andExpect(jsonPath("$.data.lastEventSequence").value(17))
        .andExpect(jsonPath("$.data.canvasState.lastEventSequence").value(17))
        .andExpect(jsonPath("$.data.canvasState.clientSavedAt").value("2026-07-22T05:30:00Z"))
        .andExpect(jsonPath("$.data.previewUrl").value("/api/v1/drawing-assets/20/file"));
  }

  @Test
  void deletesDraftWithoutResponseBody() throws Exception {
    mockMvc
        .perform(delete("/api/v1/drawing-sessions/{id}/draft", 10L))
        .andExpect(status().isNoContent());

    verify(drawingDraftService).delete(10L);
  }

  private MockMultipartFile preview() {
    return new MockMultipartFile("preview", "draft.png", "image/png", new byte[] {1, 2, 3});
  }

  private MockMultipartFile canvasState(long sequence, boolean includeSavedAt) {
    String json =
        includeSavedAt
            ? "{\"lastEventSequence\":"
                + sequence
                + ",\"clientSavedAt\":\"2026-07-22T14:30:00+09:00\"}"
            : "{\"lastEventSequence\":" + sequence + "}";
    return canvasState(json);
  }

  private MockMultipartFile canvasState(String json) {
    return new MockMultipartFile(
        "canvasState", "canvas-state.json", MediaType.APPLICATION_JSON_VALUE, json.getBytes());
  }

  private DrawingDraftResponse response() {
    return new DrawingDraftResponse(
        20L,
        10L,
        DrawingAssetType.DRAFT,
        3,
        17,
        false,
        "image/png",
        3,
        Instant.parse("2026-07-22T05:30:00Z"),
        Instant.parse("2026-07-22T05:30:01Z"),
        null,
        "/api/v1/drawing-assets/20/file",
        new DrawingCanvasStateResponse(17, Instant.parse("2026-07-22T05:30:00Z")));
  }
}
