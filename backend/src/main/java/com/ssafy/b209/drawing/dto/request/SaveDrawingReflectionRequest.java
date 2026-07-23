package com.ssafy.b209.drawing.dto.request;

import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * 그림 활동을 돌아보며 작성한 제목과 아동이 직접 선택한 감정 표현을 전달한다.
 *
 * @param title 그림 제목, 작성하지 않은 경우 {@code null}
 * @param selectedEmotions 아동이 선택한 감정 코드 목록
 * @param expressedEmotionText 아동이 직접 표현한 감정 내용, 작성하지 않은 경우 {@code null}; 최대 16,000자
 * @param skipped 아동이 감정 선택을 건너뛰었는지 여부
 */
public record SaveDrawingReflectionRequest(
    @Size(max = 200) String title,
    @NotNull @Size(max = 6) List<@NotNull DrawingEmotionCode> selectedEmotions,
    @Size(max = 16_000) String expressedEmotionText,
    boolean skipped) {

  /** 외부에서 전달된 가변 목록이 요청 생성 후 변경되지 않도록 복사한다. */
  public SaveDrawingReflectionRequest {
    selectedEmotions = selectedEmotions == null ? null : List.copyOf(selectedEmotions);
  }
}
