package com.ssafy.b209.conversation.dto;

import java.util.List;

/** 실제 저장된 AI 또는 템플릿 질문의 안전한 결과다. */
public record GeneratedQuestion(
    Long messageId,
    String questionText,
    boolean fallbackUsed,
    int sequence,
    List<QuestionOption> options,
    DetectedObject targetObject,
    String confirmedStopTarget) {

  /**
   * 종료 확인 신호가 없는 저장 결과를 생성한다(S15P11B209-951 이전 형태).
   *
   * @param messageId 저장된 메시지 식별자
   * @param questionText 저장된 질문 본문
   * @param fallbackUsed 폴백 템플릿 사용 여부
   * @param sequence 대화 내 순번
   * @param options 선택 칩 목록
   * @param targetObject 질문이 가리키는 탐지 객체
   */
  public GeneratedQuestion(
      Long messageId,
      String questionText,
      boolean fallbackUsed,
      int sequence,
      List<QuestionOption> options,
      DetectedObject targetObject) {
    this(messageId, questionText, fallbackUsed, sequence, options, targetObject, null);
  }

  /**
   * 기존 내부 호출에 호환되는 최소 저장 결과를 생성한다.
   *
   * @param messageId 저장된 메시지 식별자
   * @param questionText 저장된 질문 본문
   * @param fallbackUsed 폴백 템플릿 사용 여부
   */
  public GeneratedQuestion(Long messageId, String questionText, boolean fallbackUsed) {
    this(messageId, questionText, fallbackUsed, 0, List.of(), null, null);
  }

  /**
   * 아이가 말로 확인한 종료 대상을 실어 새 결과를 만든다(S15P11B209-951).
   *
   * <p>저장 계층은 이 값을 모른다 — 질문 메시지에 남길 내용이 아니라 이번 응답에만 실리는 신호이기 때문이다.
   *
   * @param target {@code CONVERSATION} 또는 {@code ACTIVITY}, 확인이 없으면 {@code null}
   * @return 종료 대상만 바뀐 새 결과
   */
  public GeneratedQuestion withConfirmedStopTarget(String target) {
    return new GeneratedQuestion(
        messageId, questionText, fallbackUsed, sequence, options, targetObject, target);
  }
}
