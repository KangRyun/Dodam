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
 * @param subjectContexts 주제(그림)별 관찰 서술·탐지 코드·문답 묶음이며 HTP는 최대 3건, 그림일기는 1건 (S15P11B209-741)
 * @param selectedEmotionRefs 선택 감정을 행 식별자와 함께 담은 목록이다. {@code selectedEmotions}와 같은 재료이며 근거 참조가 가능한
 *     형태다 (S15P11B209-906)
 * @param activitySessionIds 이 리포트가 다루는 그림 활동 세션 식별자 목록이다. HTP는 집·나무·사람 세 건, 그림일기·단독 세션은 한 건이다. 행동
 *     요약(S15P11B209-870)을 세션별로 집계해 합칠 때 쓴다 — HTP 리포트는 세 활동을 합친 기록이다
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
    List<KeyConversationLine> keyConversations,
    List<SubjectContext> subjectContexts,
    List<SelectedEmotionRef> selectedEmotionRefs,
    List<Long> activitySessionIds) {

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
   * @param sttNeedsConfirmation 음성 인식 결과에 보호자 확인이 필요한 답변인지 여부다. 미확정 발화는 문답 표시에는 남기지만 근거·대표 발화에서는
   *     제외한다(보호자 계약 §4-4)
   */
  public record KeyConversationLine(
      Long questionMessageId,
      String questionText,
      Long answerMessageId,
      String answerText,
      String answerType,
      boolean sttNeedsConfirmation) {}

  /**
   * 그림에서 탐지된 객체 하나를 <strong>서버가 발급한 행 식별자와 함께</strong> 담는다 (S15P11B209-906).
   *
   * <p>코드값만 보내면 AI 가 근거를 가리킬 때 조합키를 조립할 수밖에 없고, 그러면 서버가 "서로 독립된 근거 2건"을 검증할 수 없어 공개 게이트가 자기 신고로
   * 무력해진다(계약 §4). 그래서 참조 가능한 식별자를 함께 보낸다.
   *
   * @param detectedObjectId 탐지 객체 행 식별자
   * @param objectCode 탐지 객체 내부 코드
   */
  public record DetectedObjectRef(Long detectedObjectId, String objectCode) {}

  /**
   * 아동이 선택한 감정 하나를 <strong>서버가 발급한 행 식별자와 함께</strong> 담는다 (S15P11B209-906).
   *
   * @param emotionId 선택 감정 행 식별자
   * @param emotionCode 감정 코드
   */
  public record SelectedEmotionRef(Long emotionId, String emotionCode) {}

  /**
   * 주제(그림) 하나의 관찰 서술·탐지 코드·문답 묶음이다 (S15P11B209-741).
   *
   * <p>AI 요청 {@code subjectSummaries}의 재료 — 매핑은 생성 서비스가 한다.
   *
   * @param drawingSubject HTP 주제 이름({@code HOUSE|TREE|PERSON})이며 그림일기는 {@code null}
   * @param drawingDescription 해당 그림의 VLM 관찰 서술이며 없으면 {@code null}
   * @param detectedObjectCodes 해당 그림에서 탐지된 객체 내부 코드 목록
   * @param qaPairs 해당 그림 대화의 질문·답변 목록
   * @param observationResultId 관찰 서술의 출처인 {@code analysis_observation_results} 행 식별자이며 서술이 없으면
   *     {@code null}이다 (S15P11B209-906)
   * @param detectedObjects 탐지 객체를 행 식별자와 함께 담은 목록이다. {@code detectedObjectCodes}와 같은 재료이며 근거 참조가
   *     가능한 형태다 (S15P11B209-906)
   */
  public record SubjectContext(
      String drawingSubject,
      String drawingDescription,
      List<String> detectedObjectCodes,
      List<KeyConversationLine> qaPairs,
      Long observationResultId,
      List<DetectedObjectRef> detectedObjects) {}
}
