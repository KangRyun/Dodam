package com.ssafy.b209.conversation.dto;

/** 리포트 대표 대화를 구성하기 위해 조회한 질문·답변 메시지 원본이다. */
public interface KeyConversationSource {

  /**
   * @return 질문 메시지 식별자
   */
  Long getQuestionMessageId();

  /**
   * @return 질문 원문
   */
  String getQuestionText();

  /**
   * @return 답변 메시지 식별자
   */
  Long getAnswerMessageId();

  /**
   * @return 답변 원문 또는 음성 인식 결과
   */
  String getAnswerText();

  /**
   * @return 답변 메시지 유형
   */
  String getAnswerType();
}
