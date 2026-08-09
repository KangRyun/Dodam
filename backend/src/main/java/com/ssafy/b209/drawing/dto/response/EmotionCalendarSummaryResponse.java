package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 월간 감정 달력의 한 달 요약을 반환한다.
 *
 * @param activityCount 해당 월의 활동 수이며 선택 감정 수에 영향받지 않는다
 * @param topEmotion 해당 월에 가장 많이 선택된 감정이며, 선택 수가 같으면 감정 코드 이름의 사전순으로 앞서는 값을 사용하고 선택 감정이 전혀 없으면
 *     {@code null}
 * @param completedReportCount 해당 월 활동에 연결된 생성 완료 리포트 수
 */
@Schema(description = "월간 감정 달력의 한 달 요약")
public record EmotionCalendarSummaryResponse(
    @Schema(description = "해당 월의 활동 수", example = "12") long activityCount,
    @Schema(description = "해당 월 최다 선택 감정", example = "HAPPY") DrawingEmotionCode topEmotion,
    @Schema(description = "해당 월 활동의 생성 완료 리포트 수", example = "5") long completedReportCount) {}
