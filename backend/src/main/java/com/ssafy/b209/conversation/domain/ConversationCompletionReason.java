package com.ssafy.b209.conversation.domain;

/** 대화가 종료된 직접적인 계기를 분류하는 DB·API 공통 코드다. */
public enum ConversationCompletionReason {
  QUESTION_LIMIT_REACHED,
  CHILD_REQUEST,
  GUARDIAN_REQUEST,
  NO_MORE_QUESTION
}
