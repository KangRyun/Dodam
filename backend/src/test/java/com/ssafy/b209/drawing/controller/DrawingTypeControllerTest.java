package com.ssafy.b209.drawing.controller;

import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.drawing.domain.DrawingActivityCategory;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.dto.response.DrawingTypePageResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeResponse;
import com.ssafy.b209.drawing.service.DrawingTypeQueryService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingTypeController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingTypeControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingTypeQueryService drawingTypeQueryService;

  @Test
  void returnsWrappedDrawingTypesWithDefaultActiveFilter() throws Exception {
    DrawingTypeResponse item =
        new DrawingTypeResponse(
            11L,
            "FREE_DRAWING",
            "자유 그리기",
            DrawingActivityCategory.GENERAL,
            DrawingTypeSelectableBy.BOTH,
            3,
            12,
            "자유롭게 그려 보세요.",
            1);
    given(drawingTypeQueryService.getDrawingTypes(7L, DrawingActivityCategory.GENERAL, true))
        .willReturn(new DrawingTypePageResponse(List.of(item), 0, 1, 1, 1, false));

    mockMvc
        .perform(
            get("/api/v1/drawing-types")
                .queryParam("childId", "7")
                .queryParam("category", "GENERAL"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.content[0].drawingTypeId").value(11))
        .andExpect(jsonPath("$.data.content[0].activityCategory").value("GENERAL"))
        .andExpect(jsonPath("$.data.content[0].selectableBy").value("BOTH"))
        .andExpect(jsonPath("$.data.content[0].guideText").value("자유롭게 그려 보세요."))
        .andExpect(jsonPath("$.data.content[0].displayOrder").value(1))
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(jsonPath("$.data.hasNext").value(false));

    verify(drawingTypeQueryService).getDrawingTypes(7L, DrawingActivityCategory.GENERAL, true);
  }

  @Test
  void rejectsMissingOrNonPositiveChildId() throws Exception {
    mockMvc.perform(get("/api/v1/drawing-types")).andExpect(status().isBadRequest());
    mockMvc
        .perform(get("/api/v1/drawing-types").queryParam("childId", "0"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsUnknownCategory() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/drawing-types")
                .queryParam("childId", "7")
                .queryParam("category", "UNKNOWN"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_002"));
  }
}
