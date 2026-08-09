package com.ssafy.b209.drawing.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.dto.response.EmotionCalendarDayResponse;
import com.ssafy.b209.drawing.dto.response.EmotionCalendarResponse;
import com.ssafy.b209.drawing.dto.response.EmotionCalendarSummaryResponse;
import com.ssafy.b209.drawing.service.EmotionCalendarQueryService;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(EmotionCalendarController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class EmotionCalendarControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private EmotionCalendarQueryService emotionCalendarQueryService;

  @Test
  void returnsMonthlyCalendarWithDaysAndSummary() throws Exception {
    given(emotionCalendarQueryService.getMonthlyCalendar(eq(3L), eq(YearMonth.of(2026, 7))))
        .willReturn(calendarWithOneDay());

    mockMvc
        .perform(
            get("/api/v1/children/3/emotions/calendar").param("year", "2026").param("month", "7"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.year").value(2026))
        .andExpect(jsonPath("$.data.month").value(7))
        .andExpect(jsonPath("$.data.days[0].date").value("2026-07-03"))
        .andExpect(jsonPath("$.data.days[0].representativeEmotion").value("HAPPY"))
        .andExpect(jsonPath("$.data.days[0].emotions[0]").value("HAPPY"))
        .andExpect(jsonPath("$.data.days[0].emotions[1]").value("CALM"))
        .andExpect(jsonPath("$.data.days[0].activityCount").value(2))
        .andExpect(jsonPath("$.data.days[0].completedReportCount").value(1))
        .andExpect(jsonPath("$.data.summary.activityCount").value(12))
        .andExpect(jsonPath("$.data.summary.topEmotion").value("HAPPY"))
        .andExpect(jsonPath("$.data.summary.completedReportCount").value(5));

    verify(emotionCalendarQueryService).getMonthlyCalendar(3L, YearMonth.of(2026, 7));
  }

  @Test
  void rejectsMonthBelowRangeWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/emotions/calendar").param("year", "2026").param("month", "0"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsMonthAboveRangeWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/emotions/calendar").param("year", "2026").param("month", "13"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsYearBelowRangeWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/emotions/calendar").param("year", "1999").param("month", "7"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsYearAboveRangeWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/emotions/calendar").param("year", "2101").param("month", "7"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void rejectsMissingMonthWithBadRequest() throws Exception {
    mockMvc
        .perform(get("/api/v1/children/3/emotions/calendar").param("year", "2026"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_004"));
  }

  @Test
  void rejectsNonNumericMonthWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/3/emotions/calendar")
                .param("year", "2026")
                .param("month", "july"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_002"));
  }

  @Test
  void rejectsNonPositiveChildIdWithBadRequest() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/0/emotions/calendar").param("year", "2026").param("month", "7"))
        .andExpect(status().isBadRequest());
  }

  @Test
  void propagatesMissingAuthenticationAsUnauthorized() throws Exception {
    given(emotionCalendarQueryService.getMonthlyCalendar(eq(3L), any(YearMonth.class)))
        .willThrow(new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED));

    mockMvc
        .perform(
            get("/api/v1/children/3/emotions/calendar").param("year", "2026").param("month", "7"))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @Test
  void propagatesChildNotFoundAsNotFound() throws Exception {
    given(emotionCalendarQueryService.getMonthlyCalendar(eq(9L), any(YearMonth.class)))
        .willThrow(new BusinessException(ChildErrorCode.CHILD_NOT_FOUND));

    mockMvc
        .perform(
            get("/api/v1/children/9/emotions/calendar").param("year", "2026").param("month", "7"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("CHILD_404_001"));
  }

  private EmotionCalendarResponse calendarWithOneDay() {
    EmotionCalendarDayResponse day =
        new EmotionCalendarDayResponse(
            LocalDate.of(2026, 7, 3),
            DrawingEmotionCode.HAPPY,
            List.of(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM),
            2,
            1);
    return new EmotionCalendarResponse(
        2026, 7, List.of(day), new EmotionCalendarSummaryResponse(12, DrawingEmotionCode.HAPPY, 5));
  }
}
