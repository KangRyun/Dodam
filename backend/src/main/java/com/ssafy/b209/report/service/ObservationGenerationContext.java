package com.ssafy.b209.report.service;

import java.math.BigDecimal;
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
 * @param activitySessions 이 리포트가 다루는 그림 활동 세션과 그 <b>주제</b> 목록이다. HTP는 집·나무·사람 세 건, 그림일기·단독 세션은 주제
 *     없는 한 건이다. 행동 요약(S15P11B209-870)을 세션별로 집계해 합칠 때 쓰고, 주제별 그리기 시간(S15P11B209-975)의 이름표가 된다 — HTP
 *     리포트는 세 활동을 합친 기록이다.
 *     <p>🔴 <b>{@code subjectContexts} 와 길이가 다르다.</b> 그쪽은 서술·탐지 코드·문답이 <b>모두 빈</b> 주제를 걸어낸 목록이라,
 *     그리기만 하고 관찰·문답이 없는 세션이 빠져 있다. 주제별 시간을 그 목록으로 매핑하면 실제로 그린 그림 하나가 통째로 사라지고 남은 둘만으로 "가장 오래 머문
 *     그림"이 정해진다. 필터링 전인 이 목록이 세션·주제의 정본이다
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
    List<ActivitySessionRef> activitySessions) {

  /** 목록이 {@code null}로 만들어져도 빈 목록으로 정규화한다. */
  public ObservationGenerationContext {
    activitySessions = activitySessions == null ? List.of() : List.copyOf(activitySessions);
  }

  /**
   * 대표 답변 중 첫 발화를 반환한다.
   *
   * @return 첫 대표 답변 문구이며 없으면 {@code null}
   */
  public String representativeUtterance() {
    return keyConversations.isEmpty() ? null : keyConversations.get(0).answerText();
  }

  /**
   * 이 리포트가 다루는 세션 식별자만 뽑는다.
   *
   * <p>주제가 필요 없는 호출부(보호자 화면용 행동 요약 등)를 위한 파생값이며 {@code activitySessions} 와 순서·개수가 같다.
   *
   * @return 세션 식별자 목록
   */
  public List<Long> activitySessionIds() {
    return activitySessions.stream().map(ActivitySessionRef::drawingSessionId).toList();
  }

  /**
   * 이 리포트가 다루는 그림 활동 세션 하나와 그 주제다 (S15P11B209-975).
   *
   * <p>서술·문답 유무와 <b>무관하게</b> 담긴다. 아이가 그림만 그리고 대화를 하지 않아도 그 시간은 실제로 그린 시간이라 주제별 기록에서 빠지면 안 된다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param drawingSubject HTP 주제({@code HOUSE|TREE|PERSON})이며 그림일기·단독 세션은 {@code null}
   */
  public record ActivitySessionRef(Long drawingSessionId, String drawingSubject) {}

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
   * <p><b>기하는 정규화 좌표만 담는다</b> (S15P11B209-836/837). AI 는 캔버스 원본 크기를 모르므로 픽셀 좌표로는 용지 점유율을 계산할 수 없다 —
   * 그래서 {@code PIXEL} 좌표계로 저장된 탐지 행은 이 목록에 담지 않는다. 담더라도 AI 가 쓸 수 없고, 픽셀값을 0~1 비율인 척 넘기면 "종이의 90%를
   * 차지한다" 같은 <b>없는 관찰</b>이 만들어진다.
   *
   * @param detectedObjectId 탐지 객체 행 식별자
   * @param objectCode 탐지 객체 내부 코드
   * @param x 0~1 정규화 좌측 상단 X 좌표
   * @param y 0~1 정규화 좌측 상단 Y 좌표
   * @param width 0~1 정규화 너비
   * @param height 0~1 정규화 높이
   * @param areaRatio 전체 그림에서 객체가 차지하는 비율이며 저장돼 있지 않으면 {@code null}. <b>{@code width * height} 로 계산해
   *     채우지 않는다</b> — 추정값을 관찰 사실로 적으면 근거가 아닌 것이 근거 자리에 들어간다
   * @param confidence 0~1 탐지 신뢰도
   */
  public record DetectedObjectRef(
      Long detectedObjectId,
      String objectCode,
      BigDecimal x,
      BigDecimal y,
      BigDecimal width,
      BigDecimal height,
      BigDecimal areaRatio,
      BigDecimal confidence) {}

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
   * @param detectedObjects 탐지 객체를 행 식별자·정규화 기하와 함께 담은 목록이다 (S15P11B209-906/837). <b>{@code
   *     detectedObjectCodes}와 개수가 다를 수 있다</b> — 코드 목록은 탐지 전부를 담지만 이쪽은 정규화 좌표가 있는 행만 담는다. 픽셀 좌표뿐인
   *     그림은 빈 목록이 되고, 그래도 코드 목록은 관찰 서술 재료로 그대로 쓰인다
   * @param drawingSessionId 이 주제의 그림 활동 세션 식별자다 (S15P11B209-960). 주제별 관찰의 완성 그림 URL 을 조회 시점에 발급하려면
   *     어느 세션의 자산인지 알아야 한다 — {@code activitySessionIds}는 순서만 같을 뿐 서술·문답이 모두 빈 주제를 걸러낸 이 목록과 길이가 달라
   *     인덱스로 짝지을 수 없다
   */
  public record SubjectContext(
      String drawingSubject,
      String drawingDescription,
      List<String> detectedObjectCodes,
      List<KeyConversationLine> qaPairs,
      Long observationResultId,
      List<DetectedObjectRef> detectedObjects,
      Long drawingSessionId) {

    /**
     * 세션 식별자가 없던 형태로 만든다 (S15P11B209-960 이전 호출부용).
     *
     * <p>세션을 모르면 주제별 완성 그림 URL 이 {@code null}이 될 뿐, 관찰 서술·문답은 그대로 실린다.
     *
     * @param drawingSubject HTP 주제이며 그림일기는 {@code null}
     * @param drawingDescription 그림의 VLM 관찰 서술이며 없으면 {@code null}
     * @param detectedObjectCodes 탐지된 객체 내부 코드 목록
     * @param qaPairs 그림 대화의 질문·답변 목록
     * @param observationResultId 관찰 서술 출처 행 식별자이며 없으면 {@code null}
     * @param detectedObjects 탐지 객체를 행 식별자·정규화 기하와 함께 담은 목록
     */
    public SubjectContext(
        String drawingSubject,
        String drawingDescription,
        List<String> detectedObjectCodes,
        List<KeyConversationLine> qaPairs,
        Long observationResultId,
        List<DetectedObjectRef> detectedObjects) {
      this(
          drawingSubject,
          drawingDescription,
          detectedObjectCodes,
          qaPairs,
          observationResultId,
          detectedObjects,
          null);
    }
  }
}
