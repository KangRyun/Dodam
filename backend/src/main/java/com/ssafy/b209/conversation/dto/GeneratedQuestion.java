package com.ssafy.b209.conversation.dto;

import java.util.List;

/** 실제 저장된 AI 또는 템플릿 질문의 안전한 결과다. */
public record GeneratedQuestion(
    Long messageId,
    String questionText,
    boolean fallbackUsed,
    int sequence,
    List<QuestionOption> options,
    DetectedObject targetObject) {

  /**
   * 기존 내부 호출에 호환되는 최소 저장 결과를 생성한다.
   *
   * @param messageId 저장된 메시지 식별자
   * @param questionText 저장된 질문 본문
   * @param fallbackUsed 폴백 템플릿 사용 여부
   */
  public GeneratedQuestion(Long messageId, String questionText, boolean fallbackUsed) {
    this(messageId, questionText, fallbackUsed, 0, List.of(), null);
  }
}
