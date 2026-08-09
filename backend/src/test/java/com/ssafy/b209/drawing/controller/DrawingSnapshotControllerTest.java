package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.dto.request.UploadDrawingSnapshotRequest;
import com.ssafy.b209.drawing.dto.response.DrawingSessionAssetSummaryResponse;
import com.ssafy.b209.drawing.dto.response.UploadDrawingSnapshotResponse;
import com.ssafy.b209.drawing.service.DrawingSessionQueryService;
import com.ssafy.b209.drawing.service.DrawingSnapshotService;
import com.ssafy.b209.storage.image.StoreImageCommand;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingSnapshotController.class)
@org.springframework.context.annotation.Import(
    com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingSnapshotControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingSnapshotService drawingSnapshotService;
  @MockitoBean private DrawingSessionQueryService drawingSessionQueryService;

  @Test
  void returnsSnapshotSummariesForTheSession() throws Exception {
    given(drawingSessionQueryService.getSnapshots(10L))
        .willReturn(
            List.of(
                new DrawingSessionAssetSummaryResponse(
                    20L,
                    DrawingAssetType.INTERMEDIATE,
                    1,
                    "image/png",
                    1024L,
                    Instant.parse("2026-07-22T00:30:00Z"),
                    Instant.parse("2026-07-22T00:30:00Z"))));

    mockMvc
        .perform(get("/api/v1/drawing-sessions/{id}/snapshots", 10L))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data[0].drawingAssetId").value(20))
        .andExpect(jsonPath("$.data[0].assetType").value("INTERMEDIATE"))
        .andExpect(jsonPath("$.data[0].storageKey").doesNotExist());
  }

  @Test
  void returnsCreatedResponseAndSnapshotLocation() throws Exception {
    MockMultipartFile file =
        new MockMultipartFile("file", "drawing.png", "image/png", new byte[] {1, 2, 3});
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {"assetType":"INTERMEDIATE","assetVersion":1,"capturedAt":"2026-07-22T09:30:00+09:00"}
            """
                .getBytes());
    given(
            drawingSnapshotService.upload(
                eq(10L), any(StoreImageCommand.class), any(UploadDrawingSnapshotRequest.class)))
        .willReturn(response());

    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/snapshots", 10L).file(file).file(metadata))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/drawing-sessions/10/snapshots/20"))
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.drawingAssetId").value(20))
        .andExpect(jsonPath("$.data.assetType").value("INTERMEDIATE"))
        .andExpect(jsonPath("$.data.storageKey").doesNotExist());
  }

  @Test
  void rejectsInvalidMetadataBeforeCallingService() throws Exception {
    MockMultipartFile file =
        new MockMultipartFile("file", "drawing.png", "image/png", new byte[] {1});
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            "{\"assetType\":\"INTERMEDIATE\",\"assetVersion\":0}".getBytes());

    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/snapshots", 10L).file(file).file(metadata))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  private UploadDrawingSnapshotResponse response() {
    return new UploadDrawingSnapshotResponse(
        20L,
        10L,
        DrawingAssetType.INTERMEDIATE,
        1,
        "image/png",
        3,
        "a".repeat(64),
        Instant.parse("2026-07-22T00:30:00Z"),
        Instant.parse("2026-07-22T01:00:00Z"));
  }
}
