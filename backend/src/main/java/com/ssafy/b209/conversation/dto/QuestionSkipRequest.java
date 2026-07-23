package com.ssafy.b209.conversation.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * 아동이 현재 AI 질문을 건너뛸 때의 요청 DTO다.
 *
 * <p>{@code reason}이 비어 있으면 {@link SkipReason#CHILD_REQUEST}로 정규화하고, {@code returnToDrawing}이
 * {@code true}이면 그림 세션을 그리기 단계로 되돌린다. 건너뛰기는 이미 카운트된 질문에 대한 표시이므로 질문 수는 되돌리지 않는다.
 *
 * @param questionMessageId 건너뛸 같은 대화 세션의 QUESTION 메시지 ID
 * @param reason 건너뛰기 사유이며 미지정 시 {@link SkipReason#CHILD_REQUEST}
 * @param returnToDrawing 그림 그리기 단계로 되돌릴지 여부이며 미지정 시 {@code false}
 */
public record QuestionSkipRequest(
    @NotNull @Positive Long questionMessageId, SkipReason reason, boolean returnToDrawing) {

  /** 선택 필드인 {@code reason}이 비어 있으면 기본값으로 정규화한다. */
  public QuestionSkipRequest {
    if (reason == null) {
      reason = SkipReason.CHILD_REQUEST;
    }
  }
}
