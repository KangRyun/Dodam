package com.ssafy.b209.conversation.dto;

import java.time.LocalDateTime;

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

  /**
   * 음성 인식 결과에 보호자 확인이 필요한 답변인지 알린다.
   *
   * <p>미확정 발화는 문답 표시에는 남기지만 <strong>근거와 대표 발화에서는 제외</strong>한다(보호자 계약 §4-4). 그 규칙이 동작하려면 이 값이 원 메시지
   * 기준 실데이터여야 한다 — 상수로 두면 조건이 참이 되지 않아 규칙 전체가 조용히 무효가 된다.
   *
   * @return 보호자 확인이 필요하면 {@code true}
   */
  boolean getAnswerNeedsGuardianConfirmation();

  /**
   * @return 음성 답변의 STT 처리 상태이며 음성 답변이 아니면 {@code null}
   */
  String getAnswerSpeechStatus();

  /**
   * @return 리포트 생성 시점에 원본 음성 저장 참조가 있으면 {@code true}
   */
  boolean getAnswerAudioAvailable();

  /**
   * @return 답변 메시지가 생성된 서버 시각
   */
  LocalDateTime getAnswerCreatedAt();
}
