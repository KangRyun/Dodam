package com.ssafy.b209.report.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportListDrawingTypeResponse;
import com.ssafy.b209.report.dto.ReportListItemResponse;
import com.ssafy.b209.report.dto.ReportListPageResponse;
import com.ssafy.b209.report.service.ReportListQueryService;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ReportListController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class ReportListControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private ReportListQueryService reportListQueryService;

  @Test
  void returnsReportPageWithDefaultPaging() throws Exception {
    given(
            reportListQueryService.getReports(
                eq(3L), isNull(), isNull(), isNull(), isNull(), any(Pageable.class)))
        .willReturn(pageWithOneItem());

    mockMvc
        .perform(get("/api/v1/children/3/reports"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.data.content[0].reportId").value(50))
        .andExpect(jsonPath("$.data.content[0].drawingType.code").value("ART_DIARY"))
        .andExpect(jsonPath("$.data.content[0].activityDate").value("2026-07-22"))
        .andExpect(jsonPath("$.data.content[0].reportStatus").value("COMPLETED"))
        .andExpect(jsonPath("$.data.totalElements").value(1));

    verify(reportListQueryService)
        .getReports(eq(3L), isNull(), isNull(), isNull(), isNull(), eq(PageRequest.of(0, 20)));
  }

  @Test
  void passesFiltersAndPagingToService() throws Exception {
    given(
            reportListQueryService.getReports(
                eq(3L),
                eq(LocalDate.of(2026, 7, 1)),
                eq(LocalDate.of(2026, 7, 10)),
                eq("ART_DIARY"),
                eq(ReportStatus.COMPLETED),
                any(Pageable.class)))
        .willReturn(pageWithOneItem());

    mockMvc
        .perform(
            get("/api/v1/children/3/reports")
                .param("from", "2026-07-01")
                .param("to", "2026-07-10")
                .param("drawingTypeCode", "ART_DIARY")
                .param("reportStatus", "COMPLETED")
                .param("page", "1")
                .param("size", "5"))
        .andExpect(status().isOk());

    verify(reportListQueryService)
        .getReports(
            3L,
            LocalDate.of(2026, 7, 1),
            LocalDate.of(2026, 7, 10),
            "ART_DIARY",
            ReportStatus.COMPLETED,
            PageRequest.of(1, 5));
  }

  @Test
  void rejectsDateRangeLongerThanOneYear() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/reports").param("from", "2025-07-01").param("to", "2026-07-02"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsFromDateAfterToDate() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/reports").param("from", "2026-07-10").param("to", "2026-07-01"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsPageSizeAboveLimit() throws Exception {
    mockMvc
        .perform(get("/api/v1/children/3/reports").param("size", "101"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  private ReportListPageResponse pageWithOneItem() {
    ReportListItemResponse item =
        new ReportListItemResponse(
            50L,
            1,
            10L,
            new ReportListDrawingTypeResponse(7L, "ART_DIARY", "그림 일기"),
            "오늘의 그림",
            "/api/v1/drawing-assets/30/content",
            LocalDate.of(2026, 7, 22),
            300000L,
            List.of("HAPPY"),
            ReportStatus.COMPLETED,
            false);
    return new ReportListPageResponse(List.of(item), 0, 20, 1, 1, true, true, false);
  }
}
