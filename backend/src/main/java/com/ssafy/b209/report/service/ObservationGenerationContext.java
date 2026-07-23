package com.ssafy.b209.report.service;

import java.util.List;

/**
 * 관찰 리포트 생성에 필요한 비민감 맥락과 실제 대화 집계를 Transaction 밖으로 전달하는 값이다.
 *
 * @param analysisId 최종 분석 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param reportId 생성 중 리포트 식별자
 * @param conversationSessionId 대화 세션 식별자이며 대화를 생략했으면 {@code null}
 * @param questionDifficulty 대화 시작 시점 질문 난이도 Snapshot이며 없으면 {@code null}
 * @param questionCount 실제 제시한 질문 수
 * @param answeredCount 실제 응답한 답변 수
 * @param skippedCount 건너뛴 질문 수
 * @param unrecognizedSpeechCount 음성 인식에 실패한 답변 수
 * @param selectedEmotions 아동이 선택한 감정 코드 목록
 * @param expressedEmotionText 아동이 직접 표현한 감정 문구이며 없으면 {@code null}
 * @param keyConversations 실제 대화에서 선별한 대표 질문·답변 목록
 */
public record ObservationGenerationContext(
    Long analysisId,
    Long drawingSessionId,
    Long reportId,
    Long conversationSessionId,
    String questionDifficulty,
    int questionCount,
    int answeredCount,
    int skippedCount,
    int unrecognizedSpeechCount,
    List<String> selectedEmotions,
    String expressedEmotionText,
    List<KeyConversationLine> keyConversations) {

  /**
   * 대표 답변 중 첫 발화를 반환한다.
   *
   * @return 첫 대표 답변 문구이며 없으면 {@code null}
   */
  public String representativeUtterance() {
    return keyConversations.isEmpty() ? null : keyConversations.get(0).answerText();
  }

  /**
   * 리포트 대표 대화를 구성하는 질문·답변 Snapshot 원본이다.
   *
   * @param questionMessageId 질문 메시지 식별자
   * @param questionText 질문 원문
   * @param answerMessageId 답변 메시지 식별자
   * @param answerText 답변 원문 또는 음성 인식 결과
   * @param answerType 답변 메시지 유형
   */
  public record KeyConversationLine(
      Long questionMessageId,
      String questionText,
      Long answerMessageId,
      String answerText,
      String answerType) {}
}
