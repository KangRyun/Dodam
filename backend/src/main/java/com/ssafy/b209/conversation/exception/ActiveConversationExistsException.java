package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.exception.BusinessException;
import java.util.Objects;

/** 기존 진행 대화의 식별자를 409 응답에 안전하게 전달하는 업무 예외다. */
public class ActiveConversationExistsException extends BusinessException {
  private final Long conversationId;

  /**
   * 기존 진행 대화의 식별자를 보관하는 충돌 예외를 생성한다.
   *
   * @param conversationId 새 요청 대신 반환할 기존 대화 세션 식별자
   * @throws NullPointerException 기존 대화 식별자가 없는 경우
   */
  public ActiveConversationExistsException(Long conversationId) {
    super(ConversationStartErrorCode.ACTIVE_CONVERSATION_EXISTS);
    this.conversationId = Objects.requireNonNull(conversationId, "conversationId must not be null");
  }

  /**
   * @return 진행 중인 기존 대화 세션 식별자
   */
  public Long getConversationId() {
    return conversationId;
  }
}
