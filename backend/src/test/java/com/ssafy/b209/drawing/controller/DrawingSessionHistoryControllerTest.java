package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.response.DrawingSessionHistoryItemResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionHistoryPageResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeSummaryResponse;
import com.ssafy.b209.drawing.service.DrawingSessionHistoryQueryService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.ReportStatus;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DrawingSessionHistoryController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class DrawingSessionHistoryControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingSessionHistoryQueryService historyQueryService;

  @Test
  void returnsHistoryPageWithDefaultPagingAndSort() throws Exception {
    given(
            historyQueryService.getHistory(
                eq(3L), isNull(), isNull(), isNull(), isNull(), isNull(), any(Pageable.class)))
        .willReturn(pageWithOneItem());

    mockMvc
        .perform(get("/api/v1/children/3/drawing-sessions"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.content[0].drawingSessionId").value(10))
        .andExpect(
            jsonPath("$.data.content[0].thumbnailUrl").value("https://cdn.example.com/t.png"))
        .andExpect(jsonPath("$.data.content[0].drawingType.code").value("HOUSE"))
        .andExpect(jsonPath("$.data.content[0].sessionStatus").value("COMPLETED"))
        .andExpect(jsonPath("$.data.content[0].selectedEmotions[0]").value("HAPPY"))
        .andExpect(jsonPath("$.data.content[0].analysisStatus").value("SUCCEEDED"))
        .andExpect(jsonPath("$.data.content[0].reportId").value(50))
        .andExpect(jsonPath("$.data.content[0].reportStatus").value("COMPLETED"))
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(jsonPath("$.data.page").value(0))
        .andExpect(jsonPath("$.data.size").value(20));

    verify(historyQueryService)
        .getHistory(
            eq(3L),
            isNull(),
            isNull(),
            isNull(),
            isNull(),
            isNull(),
            eq(historyPage(0, 20, Sort.Direction.DESC, "startedAt")));
  }

  @Test
  void passesFiltersAndPagingToService() throws Exception {
    given(
            historyQueryService.getHistory(
                eq(3L),
                eq(LocalDate.of(2026, 7, 1)),
                eq(LocalDate.of(2026, 7, 10)),
                eq("HOUSE"),
                eq(DrawingSessionStatus.COMPLETED),
                eq(ReportStatus.COMPLETED),
                any(Pageable.class)))
        .willReturn(pageWithOneItem());

    mockMvc
        .perform(
            get("/api/v1/children/3/drawing-sessions")
                .param("from", "2026-07-01")
                .param("to", "2026-07-10")
                .param("drawingTypeCode", "HOUSE")
                .param("sessionStatus", "COMPLETED")
                .param("reportStatus", "COMPLETED")
                .param("page", "1")
                .param("size", "5")
                .param("sort", "completedAt,asc"))
        .andExpect(status().isOk());

    verify(historyQueryService)
        .getHistory(
            eq(3L),
            eq(LocalDate.of(2026, 7, 1)),
            eq(LocalDate.of(2026, 7, 10)),
            eq("HOUSE"),
            eq(DrawingSessionStatus.COMPLETED),
            eq(ReportStatus.COMPLETED),
            eq(historyPage(1, 5, Sort.Direction.ASC, "completedAt")));
  }

  @Test
  void rejectsFromAfterToWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/drawing-sessions")
                .param("from", "2026-07-10")
                .param("to", "2026-07-01"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsUnknownSortFieldWithBadRequest() throws Exception {
    mockMvc
        .perform(get("/api/v1/children/3/drawing-sessions").param("sort", "riskLevel,desc"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsSizeAboveLimitWithBadRequest() throws Exception {
    mockMvc
        .perform(get("/api/v1/children/3/drawing-sessions").param("size", "101"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsMalformedSortWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/drawing-sessions").param("sort", "startedAt,desc,unexpected"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsPageOffsetBeyondJpaLimitWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/drawing-sessions")
                .param("page", String.valueOf(Integer.MAX_VALUE))
                .param("size", "100"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsUnknownSessionStatusEnumWithBadRequest() throws Exception {
    mockMvc
        .perform(get("/api/v1/children/3/drawing-sessions").param("sessionStatus", "ARCHIVED"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_002"));
  }

  @Test
  void rejectsNonPositiveChildIdWithBadRequest() throws Exception {
    mockMvc.perform(get("/api/v1/children/0/drawing-sessions")).andExpect(status().isBadRequest());
  }

  @Test
  void propagatesChildNotFoundAsNotFound() throws Exception {
    given(
            historyQueryService.getHistory(
                eq(9L), isNull(), isNull(), isNull(), isNull(), isNull(), any(Pageable.class)))
        .willThrow(new BusinessException(ChildErrorCode.CHILD_NOT_FOUND));

    mockMvc
        .perform(get("/api/v1/children/9/drawing-sessions"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("CHILD_404_001"));
  }

  private DrawingSessionHistoryPageResponse pageWithOneItem() {
    DrawingSessionHistoryItemResponse item =
        new DrawingSessionHistoryItemResponse(
            10L,
            "https://cdn.example.com/t.png",
            new DrawingTypeSummaryResponse(7L, "HOUSE", "집"),
            "우리 집",
            DrawingInputMethod.CANVAS,
            DrawingSessionStatus.COMPLETED,
            DrawingStage.COMPLETED,
            List.of(DrawingEmotionCode.HAPPY),
            DrawingAnalysisStatus.SUCCEEDED,
            50L,
            ReportStatus.COMPLETED,
            Instant.parse("2026-07-22T04:00:00Z"),
            Instant.parse("2026-07-22T04:30:00Z"));
    return new DrawingSessionHistoryPageResponse(List.of(item), 0, 20, 1, 1, true, true, false);
  }

  private PageRequest historyPage(int page, int size, Sort.Direction direction, String property) {
    Sort sort =
        Sort.by(
            new Sort.Order(direction, property, Sort.NullHandling.NULLS_LAST),
            new Sort.Order(direction, "id"));
    return PageRequest.of(page, size, sort);
  }
}
