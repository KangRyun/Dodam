package com.ssafy.b209.drawing.controller;

import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.drawing.dto.response.DrawingAssetFileResource;
import com.ssafy.b209.drawing.service.DrawingAssetFileQueryService;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.ByteArrayInputStream;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@WebMvcTest(DrawingAssetFileController.class)
class DrawingAssetFileControllerWebMvcTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingAssetFileQueryService drawingAssetFileQueryService;

  @Test
  void servesTheDrawingAssetFileEndpointAsAStreamingResponse() throws Exception {
    byte[] bytes = {1, 2, 3, 4};
    given(drawingAssetFileQueryService.getFile(20L))
        .willReturn(
            new DrawingAssetFileResource(
                new StoredImageContent(
                    new ByteArrayInputStream(bytes), "image/png", bytes.length)));

    MvcResult asyncResult =
        mockMvc
            .perform(get("/api/v1/drawing-assets/{drawingAssetId}/file", 20L))
            .andExpect(request().asyncStarted())
            .andReturn();

    mockMvc
        .perform(asyncDispatch(asyncResult))
        .andExpect(status().isOk())
        .andExpect(header().string("Content-Type", "image/png"))
        .andExpect(header().longValue("Content-Length", bytes.length))
        .andExpect(header().string("Cache-Control", "no-store, private"))
        .andExpect(content().bytes(bytes));
  }
}
