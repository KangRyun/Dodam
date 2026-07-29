package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.UploadDrawingImageRequest;
import com.ssafy.b209.drawing.dto.response.UploadDrawingImageResponse;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.service.DrawingImageUploadService;
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

@WebMvcTest(DrawingImageUploadController.class)
@org.springframework.context.annotation.Import(
    com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingImageUploadControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingImageUploadService service;

  @Test
  void uploadsImageAndMetadataWithIdempotencyKey() throws Exception {
    MockMultipartFile image =
        new MockMultipartFile("image", "house.png", "image/png", new byte[] {1});
    MockMultipartFile metadata =
        new MockMultipartFile(
            "metadata",
            "metadata.json",
            MediaType.APPLICATION_JSON_VALUE,
            """
            {"clientCapturedAt":"2026-07-29T09:30:00+09:00","rotationDegrees":0,"cropApplied":true}
            """
                .getBytes());
    given(
            service.upload(
                eq(10L),
                eq("htp-upload-key-0001"),
                any(StoreImageCommand.class),
                any(UploadDrawingImageRequest.class)))
        .willReturn(response());

    mockMvc
        .perform(
            multipart("/api/v1/drawing-sessions/{id}/upload", 10L)
                .file(image)
                .file(metadata)
                .header("Idempotency-Key", "htp-upload-key-0001"))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/drawing-assets/30/file"))
        .andExpect(jsonPath("$.data.assetType").value("UPLOADED"))
        .andExpect(jsonPath("$.data.drawingSubject").value("HOUSE"))
        .andExpect(jsonPath("$.data.currentStage").value("DRAWING"))
        .andExpect(jsonPath("$.data.storageKey").doesNotExist());
  }

  private UploadDrawingImageResponse response() {
    return new UploadDrawingImageResponse(
        10L,
        30L,
        DrawingAssetType.UPLOADED,
        HtpDrawingSubject.HOUSE,
        DrawingStage.DRAWING,
        "/api/v1/drawing-assets/30/file",
        "image/png",
        100,
        1200,
        800,
        Instant.parse("2026-07-29T00:30:00Z"),
        Instant.parse("2026-07-29T01:00:00Z"),
        List.of());
  }
}
