package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingStage;
import java.util.List;

/**
 * 그림 활동 감정 표현 저장 결과를 반환한다.
 *
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param currentStage 저장 후 그림 활동 단계
 * @param selectedEmotions 저장된 감정 코드 목록
 * @param skipped 감정 선택을 건너뛰었는지 여부
 */
public record DrawingReflectionResponse(
    Long drawingSessionId,
    DrawingStage currentStage,
    List<DrawingEmotionCode> selectedEmotions,
    boolean skipped) {

  /** 응답 이후 목록이 변경되지 않도록 저장 결과를 복사한다. */
  public DrawingReflectionResponse {
    selectedEmotions = List.copyOf(selectedEmotions);
  }
}
