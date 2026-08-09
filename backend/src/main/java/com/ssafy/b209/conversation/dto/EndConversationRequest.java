package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * 보호자가 대화를 종료할 때 종료 사유와 화면이 확인한 마지막 질문을 전달하는 요청 계약이다.
 *
 * @param reason 대화를 종료한 직접 사유
 * @param lastQuestionMessageId 화면이 확인한 마지막 QUESTION 메시지 식별자, 생략 가능
 */
public record EndConversationRequest(
    @NotNull ConversationCompletionReason reason, @Positive Long lastQuestionMessageId) {}
