package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * 아이가 현재 질문에 답하지 않고 넘어갈 때 전달하는 요청 계약이다(§12.8).
 *
 * <p>{@code reason}은 명세 §12.8이 건너뛰기와 종료에 같은 어휘를 쓰므로 {@link ConversationCompletionReason}을 재사용한다. 저장
 * 컬럼이 없어 이력으로 남지 않는 관측 정보이며, 값이 없어도 건너뛰기는 성립한다.
 *
 * @param questionMessageId 건너뛸 AI 질문 메시지 식별자
 * @param reason 건너뛴 사유, 생략 가능
 * @param returnToDrawing 그림 단계로 되돌릴지 여부. 현재 지원하지 않으며 {@code true}면 요청을 거절한다
 */
public record SkipQuestionRequest(
    @NotNull @Positive Long questionMessageId,
    ConversationCompletionReason reason,
    Boolean returnToDrawing) {

  /**
   * 그림 단계 복귀를 요청했는지 판단한다.
   *
   * @return {@code returnToDrawing}이 명시적으로 {@code true}인 경우에만 참
   */
  public boolean requestsReturnToDrawing() {
    return Boolean.TRUE.equals(returnToDrawing);
  }
}
