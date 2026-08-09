package com.ssafy.b209.drawing.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 보호자가 조회한 아동의 월간 감정 달력을 반환한다.
 *
 * <p>일자와 월 경계는 달력 기준 시간대로 해석하며 활동이 없는 날은 {@code days}에 포함하지 않는다. 아동이 직접 선택한 감정만 담으며 AI 추정 감정과 위험도,
 * 전문가 전용 정보는 포함하지 않는다.
 *
 * @param year 조회한 연도
 * @param month 조회한 월(1~12)
 * @param days 활동이 있는 날만 일자 오름차순으로 담은 하루 요약 목록
 * @param summary 조회한 달 전체의 활동·감정 요약
 */
@Schema(description = "월간 감정 달력")
public record EmotionCalendarResponse(
    @Schema(description = "조회한 연도", example = "2026") int year,
    @Schema(description = "조회한 월", example = "7") int month,
    @Schema(description = "활동이 있는 날의 요약 목록") List<EmotionCalendarDayResponse> days,
    @Schema(description = "조회한 달의 요약") EmotionCalendarSummaryResponse summary) {

  /** 응답의 일자 목록을 외부에서 변경할 수 없도록 복사한다. */
  public EmotionCalendarResponse {
    days = List.copyOf(days);
  }
}
