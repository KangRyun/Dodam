package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.SaveDrawingReflectionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingReflectionResponse;
import com.ssafy.b209.drawing.service.DrawingReflectionService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingReflectionController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingReflectionControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingReflectionService drawingReflectionService;

  @Test
  void savesReflectionAndReturnsCurrentStage() throws Exception {
    given(drawingReflectionService.save(eq(10L), any(SaveDrawingReflectionRequest.class)))
        .willReturn(
            new DrawingReflectionResponse(
                10L,
                DrawingStage.REFLECTION,
                List.of(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM),
                false));

    mockMvc
        .perform(
            put("/api/v1/drawing-sessions/{drawingSessionId}/reflection", 10L)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "title": "우리 가족",
                      "selectedEmotions": ["HAPPY", "CALM"],
                      "expressedEmotionText": "함께 있어서 좋았어",
                      "skipped": false
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.drawingSessionId").value(10))
        .andExpect(jsonPath("$.data.currentStage").value("REFLECTION"))
        .andExpect(jsonPath("$.data.selectedEmotions[0]").value("HAPPY"))
        .andExpect(jsonPath("$.data.selectedEmotions[1]").value("CALM"))
        .andExpect(jsonPath("$.data.skipped").value(false));
  }

  @Test
  void rejectsMissingEmotionArrayBeforeServiceCall() throws Exception {
    mockMvc
        .perform(
            put("/api/v1/drawing-sessions/{drawingSessionId}/reflection", 10L)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"skipped\":false}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    verifyNoInteractions(drawingReflectionService);
  }

  @Test
  void rejectsNonPositiveSessionId() throws Exception {
    mockMvc
        .perform(
            put("/api/v1/drawing-sessions/{drawingSessionId}/reflection", 0L)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"selectedEmotions\":[\"HAPPY\"],\"skipped\":false}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    verifyNoInteractions(drawingReflectionService);
  }
}
