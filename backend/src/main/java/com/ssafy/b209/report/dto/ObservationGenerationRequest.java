package com.ssafy.b209.report.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import java.math.BigDecimal;
import java.util.List;

/**
 * Spring Boot가 관찰 리포트 생성 AI에 전달하는 최종 분석 요청 계약이다.
 *
 * <p>아동 이름·생년월일 등 식별 개인정보와 이미지·음성 원문은 포함하지 않고, 관찰에 필요한 집계 수치와 비민감 맥락만 전달한다.
 *
 * @param requestId 호출 추적과 응답 연결에 사용하는 요청 식별자
 * @param analysisId 최종 분석 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param analysisType 수행할 분석 유형이며 최종 분석은 {@code FINAL}
 * @param questionDifficulty 대화 시작 시점 질문 난이도 Snapshot이며 없으면 {@code null}
 * @param questionCount 실제 제시한 질문 수
 * @param answeredCount 실제 응답한 답변 수
 * @param skippedCount 건너뛴 질문 수
 * @param unrecognizedSpeechCount 음성 인식에 실패한 답변 수
 * @param selectedEmotions 아동이 선택한 감정 코드 목록
 * @param expressedEmotionText 아동이 직접 표현한 감정 문구이며 없으면 {@code null}
 * @param representativeUtterance 대표 발화이며 없으면 {@code null}
 * @param subjectSummaries 주제별 그림 서술·문답 묶음이며 HTP는 최대 3건(집·나무·사람), 그림일기는 1건 (S15P11B209-740)
 * @param selectedEmotionRefs 선택 감정을 <strong>서버가 발급한 행 식별자</strong>와 함께 담은 목록이다. {@code
 *     selectedEmotions}와 같은 재료이며 AI가 근거({@code sourceRef})로 가리킬 수 있는 형태다 (S15P11B209-906)
 * @param behaviorMetrics 캔버스 과정에서 집계한 형식 지표이며 집계하지 못했으면 {@code null} (S15P11B209-837)
 * @param childAge 활동 시점 기준 아동 만 나이이며 없으면 {@code null} (S15P11B209-1001)
 */
public record ObservationGenerationRequest(
    @NotBlank String requestId,
    @NotNull @Positive Long analysisId,
    @NotNull @Positive Long drawingSessionId,
    @NotBlank String analysisType,
    String questionDifficulty,
    @PositiveOrZero int questionCount,
    @PositiveOrZero int answeredCount,
    @PositiveOrZero int skippedCount,
    @PositiveOrZero int unrecognizedSpeechCount,
    List<String> selectedEmotions,
    String expressedEmotionText,
    String representativeUtterance,
    List<SubjectSummary> subjectSummaries,
    List<SelectedEmotionRef> selectedEmotionRefs,
    BehaviorMetrics behaviorMetrics,
    Integer childAge) {

  /** 목록 필드가 {@code null}로 만들어져도 빈 목록으로 정규화한다(계약: optional·기본 빈 목록). */
  public ObservationGenerationRequest {
    subjectSummaries = subjectSummaries == null ? List.of() : List.copyOf(subjectSummaries);
    selectedEmotionRefs =
        selectedEmotionRefs == null ? List.of() : List.copyOf(selectedEmotionRefs);
  }

  /**
   * 837 이전 형태로 요청을 만드는 호출부와의 호환용 생성자다. 행동 지표 없이 보낸다.
   *
   * @param requestId 호출 추적과 응답 연결에 사용하는 요청 식별자
   * @param analysisId 최종 분석 식별자
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param analysisType 수행할 분석 유형
   * @param questionDifficulty 질문 난이도 Snapshot
   * @param questionCount 실제 제시한 질문 수
   * @param answeredCount 실제 응답한 답변 수
   * @param skippedCount 건너뛴 질문 수
   * @param unrecognizedSpeechCount 음성 인식에 실패한 답변 수
   * @param selectedEmotions 아동이 선택한 감정 코드 목록
   * @param expressedEmotionText 아동이 직접 표현한 감정 문구
   * @param representativeUtterance 대표 발화
   * @param subjectSummaries 주제별 그림 서술·문답 묶음
   * @param selectedEmotionRefs 선택 감정과 행 식별자 쌍 목록
   */
  public ObservationGenerationRequest(
      String requestId,
      Long analysisId,
      Long drawingSessionId,
      String analysisType,
      String questionDifficulty,
      int questionCount,
      int answeredCount,
      int skippedCount,
      int unrecognizedSpeechCount,
      List<String> selectedEmotions,
      String expressedEmotionText,
      String representativeUtterance,
      List<SubjectSummary> subjectSummaries,
      List<SelectedEmotionRef> selectedEmotionRefs) {
    this(
        requestId,
        analysisId,
        drawingSessionId,
        analysisType,
        questionDifficulty,
        questionCount,
        answeredCount,
        skippedCount,
        unrecognizedSpeechCount,
        selectedEmotions,
        expressedEmotionText,
        representativeUtterance,
        subjectSummaries,
        selectedEmotionRefs,
        null,
        null);
  }

  /**
   * 캔버스 과정에서 집계한 형식 지표다 (S15P11B209-837).
   *
   * <p>AI 계약 {@code BehaviorMetrics}({@code ai/internal_contracts.py})와 <b>필드 1:1</b>이며 JSON 은
   * camelCase 다. 필드를 늘리거나 이름을 바꾸면 양쪽을 함께 고쳐야 한다.
   *
   * <p><b>이 객체 자체가 {@code null} 이면 "집계하지 못했다"는 뜻이고, AI 는 {@code [형식적 분석]} 블록을 아예 만들지 않는다.</b> HTP 세
   * 단계 중 하나라도 집계할 수 없으면(예: 사진 업로드 단계) 부분 합을 보내지 않고 전체를 {@code null} 로 둔다 — 두 단계만 더한 값이 활동 전체의 기록으로
   * 프롬프트에 실리면 AI 가 그것을 관찰 사실로 문장에 옮긴다.
   *
   * <p>🔴 <b>개별 항목의 {@code null} 과 {@code 0} 은 다른 뜻이다.</b> {@code null} 은 "집계하지 못함"이라 AI 가 그 줄을 빼고,
   * {@code 0} 은 "0회"라는 관찰 사실이라 그대로 적는다. 집계 실패를 0으로 채우면 <b>"멈춤 없이 몰입해서 그렸다"는 없는 관찰</b>이 리포트에 실린다.
   * Wrapper Type 을 쓰는 이유가 이것이며 절대 기본형으로 바꾸지 말 것 — {@link
   * com.ssafy.b209.drawing.service.StrokeBehaviorSummary} javadoc 과 AI 쪽 docstring 이 같은 원칙을 양쪽에서
   * 못박고 있다.
   *
   * @param drawingDurationMs 그림 전체 경과 시간(ms)이며 집계하지 못했으면 {@code null}
   * @param activeDrawingMs 실제로 획을 그린 시간의 합(ms)이며 집계하지 못했으면 {@code null}
   * @param strokeCount 그은 획의 수이며 집계하지 못했으면 {@code null} (S15P11B209-975). <b>지우개 획을 포함하므로 {@code
   *     eraseCount} 와 세는 대상이 겹친다</b> — 두 값으로 지우기 비율 같은 파생 수치를 만들지 말 것. 계약에 파생 필드를 싣지 않고 실측값 둘만 보내는
   *     이유가 이것이다
   * @param pauseCount 멈춤 횟수이며 집계하지 못했으면 {@code null}
   * @param undoCount 실행 취소 횟수이며 집계하지 못했으면 {@code null}
   * @param eraseCount 지우기 횟수이며 집계하지 못했으면 {@code null}
   * @param toolChangeCount 도구를 바꾼 횟수이며 집계하지 못했으면 {@code null}
   * @param colorChangeCount 색을 바꾼 횟수이며 집계하지 못했으면 {@code null}
   * @param colorsUsedCount 실제로 획을 그린 색의 <b>가짓수</b>이며 집계하지 못했으면 {@code null} (S15P11B209-975). 색을 바꾼
   *     <i>횟수</i>({@code colorChangeCount})와 다른 값이다. HTP 합산에서도 세 단계의 색을 <b>합집합</b>으로 세므로 세 장에 모두 쓴
   *     색이 3가지로 계수되지 않는다. 색 코드 자체는 관찰 재료가 아니라 보내지 않는다
   * @param pressureAvailable 필압 데이터가 저장돼 있는지 여부다. <b>측정 가능 여부일 뿐 필압의 강약도 감정 근거도 아니다</b>
   * @param averagePressure 평균 필압이며 <b>현재 항상 {@code null}</b> 이다. 집계기가 이 값을 만들지 않는다 — 자리만 계약에 맞춰 두고
   *     값을 지어내지 않는다
   * @param truncated 배치 수 상한에 걸려 세션 앞부분만 집계했는지 여부. {@code true}면 위 값 전부가 부분 집계다
   * @param subjectDurations HTP 주제별 그리기 시간 내역이며 그림일기·단독 세션은 <b>빈 목록</b>이다 (S15P11B209-975). 이 목록이
   *     실린다는 것은 <b>세 주제를 모두 집계했다</b>는 뜻이다 — 부분 목록은 만들어질 수 없다. 근거는 {@link
   *     com.ssafy.b209.drawing.service.StrokeBehaviorAggregate} javadoc
   */
  public record BehaviorMetrics(
      Long drawingDurationMs,
      Long activeDrawingMs,
      Integer strokeCount,
      Integer pauseCount,
      Integer undoCount,
      Integer eraseCount,
      Integer toolChangeCount,
      Integer colorChangeCount,
      Integer colorsUsedCount,
      boolean pressureAvailable,
      BigDecimal averagePressure,
      boolean truncated,
      List<SubjectDuration> subjectDurations) {

    /** 목록이 {@code null}로 만들어져도 빈 목록으로 정규화한다(계약: optional·기본 빈 목록). */
    public BehaviorMetrics {
      subjectDurations = subjectDurations == null ? List.of() : List.copyOf(subjectDurations);
    }
  }

  /**
   * HTP 주제 하나에 머문 시간이다 (S15P11B209-975).
   *
   * <p>AI 계약 {@code SubjectDuration}({@code ai/internal_contracts.py})과 필드 1:1이며 JSON 은 camelCase
   * 다.
   *
   * <p><b>비교 관찰의 재료다.</b> "어느 그림에 더 오래 머물렀는가"는 주제가 전부 실렸을 때만 참이므로, 한 단계라도 집계할 수 없으면 {@code
   * behaviorMetrics} 전체가 {@code null} 이 되어 이 목록도 함께 사라진다. 부분 목록으로 순위를 매기면 아이에 대한 없는 관찰이 만들어진다.
   *
   * @param drawingSubject HTP 주제({@code HOUSE|TREE|PERSON})
   * @param drawingDurationMs 그 주제에 머문 전체 경과 시간(ms)이며 집계하지 못했으면 {@code null}
   * @param activeDrawingMs 그 주제에서 실제로 획을 그린 시간의 합(ms)이며 집계하지 못했으면 {@code null}
   */
  public record SubjectDuration(
      String drawingSubject, Long drawingDurationMs, Long activeDrawingMs) {}

  /**
   * 주제(집/나무/사람 또는 그림일기 단일 그림) 하나의 관찰 서술·문답 묶음이다 (S15P11B209-740).
   *
   * <p>AI 계약({@code docs/ai/ai-observation-report-contract.md})과 1:1 — 필드 변경은 양쪽 동시 반영.
   *
   * @param drawingSubject HTP 주제({@code HOUSE|TREE|PERSON})이며 그림일기는 {@code null}
   * @param drawingDescription 해당 그림의 VLM 관찰 서술이며 없으면 {@code null}
   * @param detectedObjectCodes 탐지 객체 내부 코드 목록(프롬프트 참고용)
   * @param qaPairs 해당 그림 대화에서 나눈 질문·답변 목록
   * @param observationEvidenceSourceId 관찰 서술의 출처인 {@code analysis_observation_results} 행 식별자를 문자열로
   *     담은 값이며 서술이 없으면 {@code null}이다. AI 계약이 {@code str} 이라 숫자로 보내면 422 다 (S15P11B209-906/837)
   * @param detectedObjects 탐지 객체를 행 식별자·정규화 기하와 함께 담은 목록이다 (S15P11B209-906/837). <b>{@code
   *     detectedObjectCodes}와 개수가 다를 수 있다</b> — 코드 목록은 탐지 전부를 담고 이쪽은 정규화 좌표가 있는 행만 담는다
   */
  public record SubjectSummary(
      String drawingSubject,
      String drawingDescription,
      List<String> detectedObjectCodes,
      List<SubjectQaPair> qaPairs,
      String observationEvidenceSourceId,
      List<SubjectDetectedObject> detectedObjects) {

    public SubjectSummary {
      detectedObjectCodes =
          detectedObjectCodes == null ? List.of() : List.copyOf(detectedObjectCodes);
      qaPairs = qaPairs == null ? List.of() : List.copyOf(qaPairs);
      detectedObjects = detectedObjects == null ? List.of() : List.copyOf(detectedObjects);
    }
  }

  /**
   * 탐지 객체 하나를 <strong>서버가 발급한 행 식별자·정규화 기하</strong>와 함께 보낸다 (S15P11B209-906/837).
   *
   * <p>코드값만 보내면 AI가 근거를 가리킬 때 조합키를 조립할 수밖에 없다. 그러면 서버가 "서로 독립된 근거 2건"을 검증할 수 없어 공개 게이트가 생성자의 자기 신고로
   * 무력해진다(계약 §4에서 조합키 금지).
   *
   * <p><b>기하는 정규화 좌표(0~1)뿐이다.</b> AI 는 캔버스 원본 크기를 모르므로 픽셀 좌표로는 용지 점유율을 계산할 수 없다 — 그래서 서버가 {@code
   * PIXEL} 행을 아예 싣지 않고, 픽셀 결과뿐인 주제는 이 목록이 빈 채로 나간다(계약 합의 사항).
   *
   * <p><b>식별자는 문자열이다.</b> AI 계약이 {@code evidence_source_id: str} 이라 숫자로 보내면 요청 전체가 422 로 거부된다 — 실제로
   * 그렇게 운영 리포트 생성이 전량 실패했다(2026-08-05). 다른 근거 식별자도 같은 규칙이다.
   *
   * @param evidenceSourceId 탐지 객체 행 식별자를 문자열로 담은 값
   * @param objectCode 탐지 객체 내부 코드
   * @param x 0~1 정규화 좌측 상단 X 좌표
   * @param y 0~1 정규화 좌측 상단 Y 좌표
   * @param width 0~1 정규화 너비
   * @param height 0~1 정규화 높이
   * @param areaRatio 전체 그림에서 객체가 차지하는 비율이며 저장돼 있지 않으면 {@code null}. <b>{@code width * height} 로 계산해
   *     채우지 않는다</b> — AI 계약이 명시한다. 추정값을 관찰 사실로 적으면 근거가 아닌 것이 근거 자리에 들어간다
   * @param confidence 0~1 탐지 신뢰도이며 없으면 {@code null}
   */
  public record SubjectDetectedObject(
      String evidenceSourceId,
      String objectCode,
      BigDecimal x,
      BigDecimal y,
      BigDecimal width,
      BigDecimal height,
      BigDecimal areaRatio,
      BigDecimal confidence) {}

  /**
   * 선택 감정 하나를 <strong>서버가 발급한 행 식별자</strong>와 함께 보낸다 (S15P11B209-906).
   *
   * <p>식별자는 문자열이다 — AI 계약이 {@code evidence_source_id: str} 이다.
   *
   * @param evidenceSourceId {@code drawing_session_emotions} 행 식별자를 문자열로 담은 값
   * @param emotionCode 감정 코드
   */
  public record SelectedEmotionRef(String evidenceSourceId, String emotionCode) {}

  /**
   * 주제별 문답 한 쌍이다.
   *
   * <p>{@code answerText}는 아이 발화(STT 텍스트·선택 칩 라벨) — 로그·예외 메시지에 원문을 남기지 않는다(가드레일 9절).
   *
   * @param question AI가 물은 질문 텍스트
   * @param answerText 아이 답변이며 없으면 {@code null}
   * @param answerType 답변 메시지 유형(예: VOICE·OPTION·SKIPPED)이며 없으면 {@code null}
   * @param questionMessageId 질문 메시지 식별자이며 없으면 {@code null} (S15P11B209-906)
   * @param answerMessageId 답변 메시지 식별자이며 없으면 {@code null}. AI가 근거를 {@code sourceRef{kind: QA_ANSWER,
   *     id}}로 되돌려 줄 때 이 값을 쓴다 (S15P11B209-906)
   * @param sttNeedsConfirmation 음성 인식 결과에 보호자 확인이 필요한 답변인지 여부다. {@code true}인 발화는 근거와 보호자 인용에서
   *     제외된다(보호자 계약 §4-4) (S15P11B209-906)
   */
  public record SubjectQaPair(
      String question,
      String answerText,
      String answerType,
      Long questionMessageId,
      Long answerMessageId,
      boolean sttNeedsConfirmation) {}
}
