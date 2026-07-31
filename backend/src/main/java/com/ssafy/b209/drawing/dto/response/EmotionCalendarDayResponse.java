package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.LocalDate;
import java.util.List;

/**
 * 월간 감정 달력의 하루 칸에 표시할 감정과 활동 요약을 반환한다.
 *
 * <p>활동이 없는 날은 응답에 포함하지 않으므로 이 항목은 항상 활동이 한 건 이상 있는 날을 뜻한다.
 *
 * @param date 달력 기준 시간대로 계산한 활동 일자
 * @param representativeEmotion 그날 가장 늦게 시작한 활동에서 아동이 처음 선택한 감정이며, 그 활동에 선택 감정이 없으면 {@code null}
 * @param emotions 그날 활동에서 아동이 선택한 감정을 중복 없이 처음 선택된 순서로 담은 목록
 * @param activityCount 그날의 활동 수이며 선택 감정 수에 영향받지 않는다
 * @param completedReportCount 그날 활동에 연결된 생성 완료 리포트 수
 */
@Schema(description = "월간 감정 달력의 하루 요약")
public record EmotionCalendarDayResponse(
    @Schema(description = "달력 기준 시간대의 활동 일자", example = "2026-07-03") LocalDate date,
    @Schema(description = "그날 마지막 활동에서 처음 선택한 감정", example = "HAPPY")
        DrawingEmotionCode representativeEmotion,
    @Schema(description = "그날 아동이 선택한 감정 목록") List<DrawingEmotionCode> emotions,
    @Schema(description = "그날의 활동 수", example = "2") long activityCount,
    @Schema(description = "그날 활동의 생성 완료 리포트 수", example = "1") long completedReportCount) {

  /** 응답의 감정 목록을 외부에서 변경할 수 없도록 복사한다. */
  public EmotionCalendarDayResponse {
    emotions = List.copyOf(emotions);
  }
}
