package com.ssafy.b209.report.dto;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * 관찰 리포트 생성 AI가 반환하는 최종 분석 결과 계약이다.
 *
 * <p>진단형 표현 없이 관찰 초안과 대화 요약, 보호자 안내를 담으며 {@code disclaimer}와 {@code limitationsText}는 필수다.
 *
 * @param requestId 요청과 응답을 연결하는 식별자
 * @param modelName 결과를 생성한 Model 이름
 * @param modelVersion 결과를 생성한 Model 버전
 * @param confidence 0 이상 1 이하의 신뢰도이며 없으면 {@code null}
 * @param observationDraft 관찰 초안이며 검토 상태를 함께 싣는다
 * @param conversationSummary 대화 요약 초안
 * @param activityNotes 객관적 활동 주의사항 목록
 * @param followUpGuides 보호자 후속 안내 목록
 * @param guardianQuestions 보호자 질문 목록
 * @param limitationsText 리포트 해석 한계 문구
 * @param publicInterpretations 보호자에게 공개할 수 있는 비진단 경향 해석 카드 목록이다. AI 가 이미 구조 게이트를 통과시킨 것만 보내지만 BE 가
 *     다시 검증한다(이중 방어, S15P11B209-901)
 * @param evidenceItems 카드가 참조하는 근거 풀이다. {@code evidenceId} 는 <strong>이 응답 안에서만 유일한 로컬 번호</strong>다
 * @param parentGuides 유형별 보호자 가이드 목록이며 유형마다 문장이 여러 개일 수 있다
 * @param crisisAlert 위기 대응 안내이며 위기 신호가 없으면 {@code null}이다. 전부 사전 검토 템플릿이며 LLM 이 만들지 않는다. {@code
 *     ABUSE_DISCLOSURE}는 가해자가 보호자일 수 있어 <strong>항상 {@code null}</strong>이다(S15P11B209-889·890)
 * @param drawnItems 아이가 그린 것 목록이다. <strong>출처는 VLM 관찰 서술이며 탐지 라벨이 아니다</strong> — AI 가 서술 원문과 대조해 걸러
 *     보낸다(S15P11B209-911). optional 이며 AI 가 싣지 않으면 빈 목록이다
 * @param subjectReports 주제(집·나무·사람)별 관찰 묶음이다 (875 §5 / S15P11B209-960). <strong>AI 는 다섯 필드 중 셋만
 *     보낸다</strong> — {@code imageUrl}·{@code qaPairs}는 BE 소유라 서버가 채운다. HTP 가 아닌 활동은 비거나 1건이다
 * @param ragReferences 리포트가 근거로 참조한 전문 자료 출처다 (S15P11B209-614). 보호자 응답의 {@code references[]}로 나가며
 *     <strong>출처 표시는 라이선스 의무(KOGL-1)</strong>라 받은 것을 버리면 안 된다
 * @param diaryInsights 그림일기 V2 구조화 결과이며 <strong>그림일기에서 근거가 검증된 경우에만</strong> 실린다. HTP 이거나 검증된 내용이
 *     하나도 없으면 {@code null}이다 — 빈 껍데기를 만들지 않는 것이 계약이라 그 구분을 살려 nullable 로 둔다. 구 AI 응답에도 없으므로 {@code
 *     null}을 정상으로 다뤄야 한다
 */
public record ObservationGenerationResult(
    String requestId,
    String modelName,
    String modelVersion,
    BigDecimal confidence,
    ObservationDraft observationDraft,
    ConversationSummaryDraft conversationSummary,
    List<String> activityNotes,
    List<FollowUpGuideDraft> followUpGuides,
    List<GuardianQuestionDraft> guardianQuestions,
    String limitationsText,
    List<DrawnItemDraft> drawnItems,
    List<PublicInterpretationDraft> publicInterpretations,
    List<EvidenceItemDraft> evidenceItems,
    List<ParentGuideDraft> parentGuides,
    CrisisAlertDraft crisisAlert,
    List<SubjectReportDraft> subjectReports,
    List<RagReferenceDraft> ragReferences,
    DiaryInsightsDraft diaryInsights) {

  /**
   * 경향 해석 계열 목록만 빈 목록으로 정규화한다.
   *
   * <p>{@code drawnItems}는 정규화하지 않는다 — 필드 생략과 의도적 빈 배열을 구분해야 하고(S15P11B209-912) 그 판단은 {@link
   * #hasDrawnItems()}가 한다. 경향 해석 계열은 그 구분이 필요 없다(빈 배열은 근거 부족이라는 정상 결과다, 875 §10).
   *
   * <p>{@code subjectReports}·{@code ragReferences}도 같은 이유로 빈 목록이 정상이다 — 그림일기는 주제가 나뉘지 않고, 검색이 실패해도
   * 리포트는 나간다(검색 실패는 차단이 아니다).
   */
  public ObservationGenerationResult {
    publicInterpretations =
        publicInterpretations == null ? List.of() : List.copyOf(publicInterpretations);
    evidenceItems = evidenceItems == null ? List.of() : List.copyOf(evidenceItems);
    parentGuides = parentGuides == null ? List.of() : List.copyOf(parentGuides);
    subjectReports = subjectReports == null ? List.of() : List.copyOf(subjectReports);
    ragReferences = ragReferences == null ? List.of() : List.copyOf(ragReferences);
    // diaryInsights 는 정규화하지 않는다 — "구조화할 것이 없었다"(null)와 "있었다"를 가르는 것이
    //   이 필드의 일이다. 빈 객체로 채우면 화면이 빈 V2 리포트를 열어 버린다.
  }

  /**
   * 그림일기 V2 확장 이전 형태로 만든다.
   *
   * <p>{@code diaryInsights} 없이 부르던 호출부(주로 테스트·Mock)를 그대로 두기 위한 생성자다. 그림일기 구조화 결과는 {@code null}로
   * 둔다.
   *
   * @param requestId 요청 식별자
   * @param modelName Model 이름
   * @param modelVersion Model 버전
   * @param confidence 신뢰도이며 없으면 {@code null}
   * @param observationDraft 관찰 초안
   * @param conversationSummary 대화 요약 초안
   * @param activityNotes 활동 주의사항 목록
   * @param followUpGuides 보호자 후속 안내 목록
   * @param guardianQuestions 보호자 질문 목록
   * @param limitationsText 한계 문구
   * @param drawnItems 그린 것 목록이며 필드 생략을 표현하려면 {@code null}
   * @param publicInterpretations 경향 해석 카드 목록
   * @param evidenceItems 근거 목록
   * @param parentGuides 보호자 가이드 목록
   * @param crisisAlert 위기 안내이며 없으면 {@code null}
   * @param subjectReports 주제별 관찰 묶음
   * @param ragReferences 참고 자료 출처 목록
   */
  public ObservationGenerationResult(
      String requestId,
      String modelName,
      String modelVersion,
      BigDecimal confidence,
      ObservationDraft observationDraft,
      ConversationSummaryDraft conversationSummary,
      List<String> activityNotes,
      List<FollowUpGuideDraft> followUpGuides,
      List<GuardianQuestionDraft> guardianQuestions,
      String limitationsText,
      List<DrawnItemDraft> drawnItems,
      List<PublicInterpretationDraft> publicInterpretations,
      List<EvidenceItemDraft> evidenceItems,
      List<ParentGuideDraft> parentGuides,
      CrisisAlertDraft crisisAlert,
      List<SubjectReportDraft> subjectReports,
      List<RagReferenceDraft> ragReferences) {
    this(
        requestId,
        modelName,
        modelVersion,
        confidence,
        observationDraft,
        conversationSummary,
        activityNotes,
        followUpGuides,
        guardianQuestions,
        limitationsText,
        drawnItems,
        publicInterpretations,
        evidenceItems,
        parentGuides,
        crisisAlert,
        subjectReports,
        ragReferences,
        null);
  }

  /**
   * 주제별 관찰·참고 자료 확장 이전 형태로 만든다 (S15P11B209-960).
   *
   * <p>위기 안내까지만 있던 호출부(주로 테스트)를 그대로 두기 위한 생성자다.
   *
   * @param requestId 요청 식별자
   * @param modelName Model 이름
   * @param modelVersion Model 버전
   * @param confidence 신뢰도이며 없으면 {@code null}
   * @param observationDraft 관찰 초안
   * @param conversationSummary 대화 요약 초안
   * @param activityNotes 활동 주의사항 목록
   * @param followUpGuides 보호자 후속 안내 목록
   * @param guardianQuestions 보호자 질문 목록
   * @param limitationsText 한계 문구
   * @param drawnItems 그린 것 목록이며 필드 생략을 표현하려면 {@code null}
   * @param publicInterpretations 경향 해석 카드 목록
   * @param evidenceItems 근거 목록
   * @param parentGuides 보호자 가이드 목록
   * @param crisisAlert 위기 안내이며 없으면 {@code null}
   */
  public ObservationGenerationResult(
      String requestId,
      String modelName,
      String modelVersion,
      BigDecimal confidence,
      ObservationDraft observationDraft,
      ConversationSummaryDraft conversationSummary,
      List<String> activityNotes,
      List<FollowUpGuideDraft> followUpGuides,
      List<GuardianQuestionDraft> guardianQuestions,
      String limitationsText,
      List<DrawnItemDraft> drawnItems,
      List<PublicInterpretationDraft> publicInterpretations,
      List<EvidenceItemDraft> evidenceItems,
      List<ParentGuideDraft> parentGuides,
      CrisisAlertDraft crisisAlert) {
    this(
        requestId,
        modelName,
        modelVersion,
        confidence,
        observationDraft,
        conversationSummary,
        activityNotes,
        followUpGuides,
        guardianQuestions,
        limitationsText,
        drawnItems,
        publicInterpretations,
        evidenceItems,
        parentGuides,
        crisisAlert,
        List.of(),
        List.of());
  }

  /**
   * 경향 해석 확장 이전 형태로 만든다.
   *
   * <p>{@code drawnItems}까지만 있던 호출부(주로 테스트)를 그대로 두기 위한 생성자다. 경향 해석 계열은 빈 목록, 위기 안내는 {@code null}로
   * 둔다.
   *
   * @param requestId 요청 식별자
   * @param modelName Model 이름
   * @param modelVersion Model 버전
   * @param confidence 신뢰도이며 없으면 {@code null}
   * @param observationDraft 관찰 초안
   * @param conversationSummary 대화 요약 초안
   * @param activityNotes 활동 주의사항 목록
   * @param followUpGuides 보호자 후속 안내 목록
   * @param guardianQuestions 보호자 질문 목록
   * @param limitationsText 한계 문구
   * @param drawnItems 그린 것 목록이며 필드 생략을 표현하려면 {@code null}
   */
  public ObservationGenerationResult(
      String requestId,
      String modelName,
      String modelVersion,
      BigDecimal confidence,
      ObservationDraft observationDraft,
      ConversationSummaryDraft conversationSummary,
      List<String> activityNotes,
      List<FollowUpGuideDraft> followUpGuides,
      List<GuardianQuestionDraft> guardianQuestions,
      String limitationsText,
      List<DrawnItemDraft> drawnItems) {
    this(
        requestId,
        modelName,
        modelVersion,
        confidence,
        observationDraft,
        conversationSummary,
        activityNotes,
        followUpGuides,
        guardianQuestions,
        limitationsText,
        drawnItems,
        List.of(),
        List.of(),
        List.of(),
        null);
  }

  /**
   * 기존 AI 배포본이 필드를 생략한 경우와, 최신 AI가 의도적으로 빈 배열을 보낸 경우를 구분한다.
   *
   * <p>전자는 과거 리포트와 같은 0.50 YOLO 폴백 대상이고, 후자는 관찰 서술에 남은 대상이 없다는 확정 결과라 빈 목록을 유지한다.
   */
  public boolean hasDrawnItems() {
    return drawnItems != null;
  }

  /**
   * @return 필드가 생략됐거나 빈 배열이면 빈 목록, 아니면 방어 복사한 항목 목록
   */
  public List<DrawnItemDraft> drawnItemsOrEmpty() {
    return drawnItems == null
        ? List.of()
        : Collections.unmodifiableList(new ArrayList<>(drawnItems));
  }

  /** 911 이전 응답을 만드는 기존 호출부와의 호환용 생성자다. */
  public ObservationGenerationResult(
      String requestId,
      String modelName,
      String modelVersion,
      BigDecimal confidence,
      ObservationDraft observationDraft,
      ConversationSummaryDraft conversationSummary,
      List<String> activityNotes,
      List<FollowUpGuideDraft> followUpGuides,
      List<GuardianQuestionDraft> guardianQuestions,
      String limitationsText) {
    this(
        requestId,
        modelName,
        modelVersion,
        confidence,
        observationDraft,
        conversationSummary,
        activityNotes,
        followUpGuides,
        guardianQuestions,
        limitationsText,
        null,
        List.of(),
        List.of(),
        List.of(),
        null);
  }

  /**
   * 아이가 그린 것 한 건이다 (S15P11B209-912 / AI 계약 S15P11B209-911).
   *
   * <p>보호자 리포트 '그린 것' 줄의 재료다. AI 는 <strong>관찰 서술 문장에 실제로 등장한 대상만</strong> 담아 보내고, 서술 원문과 대조해 통과하지
   * 못한 항목은 AI 쪽 코드가 버린다. 탐지 라벨(YOLO)은 근거가 아니다 — 탐지 임계값 0.20 은 "박스를 남길지"의 기준이라 그 이름을 보호자에게 확정 사실로 적을
   * 수 없다.
   *
   * @param drawingSubject HTP 주제({@code HOUSE|TREE|PERSON})이며 그림일기는 {@code null}
   * @param name 보호자 화면에 그대로 나가는 한국어 표현
   */
  public record DrawnItemDraft(String drawingSubject, String name) {}

  /**
   * 주제(집·나무·사람) 하나의 관찰 묶음이다 (875 §5 / AI 계약 {@code SubjectReportDraft}).
   *
   * <p><strong>875 §5 의 다섯 필드 중 셋만 온다.</strong> 나머지 둘은 BE 소유라 AI 가 의도적으로 보내지 않는다(S15P11B209-941):
   *
   * <ul>
   *   <li>{@code imageUrl} — BE 가 가진 자산 URL 이다. AI 가 만들 수 있는 값이 아니다
   *   <li>{@code qaPairs} — 요청에 실려 온 아이 발화 원문이다. LLM 을 통과시켜 되돌려 받으면 아이 말이 바뀔 여지만 생긴다
   * </ul>
   *
   * <p>{@code interpretationRefs}는 <strong>AI 응답의 {@code publicInterpretations} 배열
   * 인덱스</strong>(0-based)이며 {@code category} 값이 아니다(875 §5-1). BE 는 이 인덱스를 저장한 카드 행으로 바꿔 두고, 응답을 낼
   * 때 <b>공개된 카드 목록에서의 위치</b>로 다시 계산한다 — 인덱스를 그대로 저장하면 서버 검증에서 카드 하나가 빠질 때 참조가 조용히 다른 카드를 가리킨다.
   *
   * @param subjectType 주제({@code HOUSE|TREE|PERSON})이며 주제가 나뉘지 않는 활동은 {@code null}
   * @param visionObservations 그 그림에서 눈으로 확인된 사실 문장 목록이며 해석은 담지 않는다
   * @param interpretationRefs 이 그림의 관찰이 근거가 된 경향 해석 카드의 배열 인덱스 목록
   */
  public record SubjectReportDraft(
      String subjectType, List<String> visionObservations, List<Integer> interpretationRefs) {

    /** 목록이 {@code null}로 와도 빈 목록으로 정규화한다. */
    public SubjectReportDraft {
      visionObservations = visionObservations == null ? List.of() : List.copyOf(visionObservations);
      interpretationRefs = interpretationRefs == null ? List.of() : List.copyOf(interpretationRefs);
    }
  }

  /**
   * 리포트가 근거로 참조한 전문 자료 출처다 (S15P11B209-614, 875 §9).
   *
   * <p>보호자 응답의 {@code references[]}로 나간다. 출처 표시는 <strong>라이선스 의무(KOGL-1)</strong>이자 보호자 신뢰 재료라 받은
   * 것을 버리지 않는다. 청크 텍스트는 오지 않는다 — {@code sourceId}·제목이면 추적에 충분하다.
   *
   * <p>URL 은 오지 않으므로 응답의 {@code references[].url}은 {@code null}이다. 875 §9 가 nullable 을 유지하기로 한 이유가
   * 이 경우다(자체 저작 자료는 URL 이 없다).
   *
   * @param sourceId 자료 출처 식별자
   * @param title 자료 제목
   */
  public record RagReferenceDraft(String sourceId, String title) {}

  /**
   * AI 가 만든 관찰 초안이다.
   *
   * @param status 검토 상태이며 {@code AI_DRAFT}(검토 안 함) 또는 {@code AI_REVIEWED}(AI 자체 검토 통과). 이 값이 {@code
   *     AI_REVIEWED}일 때만 {@code features}의 {@code REVIEWED_GUARDIAN} 항목이 보호자에게 열린다. 모르는 값은 서버가
   *     {@code AI_DRAFT}로 떨어뜨린다
   * @param overallSummary 보호자에게 노출 가능한 전체 관찰 요약
   * @param positiveSignals 관찰된 긍정 신호
   * @param attentionPoints 보호자에게 바로 노출하지 않는 내부 검토용 관찰 필요 지점
   * @param evidenceSummary 관찰 근거 요약
   * @param guardianGuidance 보호자 안내 문구
   * @param followUpQuestion 보호자가 활용할 후속 질문
   * @param expertReviewRequired <b>사람 상담 권유가 필요한 신호</b>인지 여부다. 사람 전문가 검토 대기열은 존재하지 않으므로 "전문가가 검토해야
   *     한다"는 뜻이 아니다
   * @param disclaimer 진단이 아님을 알리는 필수 주의 문구
   * @param features 관찰 특징 목록
   */
  public record ObservationDraft(
      String status,
      String overallSummary,
      String positiveSignals,
      String attentionPoints,
      String evidenceSummary,
      String guardianGuidance,
      String followUpQuestion,
      boolean expertReviewRequired,
      String disclaimer,
      List<ObservedFeatureDraft> features) {}

  /**
   * 관찰 특징 초안이다.
   *
   * @param featureCode 관찰 특징 코드
   * @param title 관찰 제목
   * @param description 관찰 내용
   * @param evidenceSummary 관찰 근거 요약
   * @param visibilityScope 노출 범위이며 {@code EXPERT_ONLY}(보호자에게 바로 열지 않음) 또는 {@code
   *     REVIEWED_GUARDIAN}(보호자 응답에 포함). 후자는 {@code ObservationDraft.status}가 {@code AI_REVIEWED}일
   *     때만 실제로 열린다
   */
  public record ObservedFeatureDraft(
      String featureCode,
      String title,
      String description,
      String evidenceSummary,
      String visibilityScope) {}

  /**
   * 대화 요약 초안이다.
   *
   * @param summaryText 관찰 보조 표현으로 작성한 대화 요약
   * @param mainTopic 대화의 주요 주제
   * @param expressedEmotion 대화에서 표현된 감정
   * @param emotionSource 표현 감정의 출처이며 {@code SELECTED}·{@code STATED}·{@code INFERRED}
   * @param representativeUtterance 대표 발화
   */
  public record ConversationSummaryDraft(
      String summaryText,
      String mainTopic,
      String expressedEmotion,
      String emotionSource,
      String representativeUtterance) {}

  /**
   * 보호자 후속 안내 초안이다.
   *
   * @param guidance 보호자 안내 문장
   * @param detailText 상세 설명
   */
  public record FollowUpGuideDraft(String guidance, String detailText) {}

  /**
   * 보호자 질문 초안이다.
   *
   * @param questionText 보호자 질문 문장
   * @param questionPurpose 질문 목적
   */
  public record GuardianQuestionDraft(String questionText, String questionPurpose) {}

  /**
   * 보호자에게 공개할 수 있는 비진단 경향 해석 카드 한 건이다 (875 §3).
   *
   * <p>필드명은 875 계약을 그대로 쓴다 — FE 가 이미 그 이름으로 DTO·화면을 구현해 병합했고, 중간에 매핑 계층을 두면 그 표가 틀릴 때 필드가 조용히 사라진다.
   *
   * @param category 관찰 관점 라벨
   * @param title 카드 제목
   * @param tendencyText 가능성 어조의 경향 문장
   * @param scopeText 해석 범위 안내이며 비면 공개 조건 미달이다
   * @param homeObservationGuide 가정에서 살펴볼 점이며 비면 공개 조건 미달이다
   * @param evidenceRefs 참조하는 근거의 로컬 번호 목록
   * @param confidence 근거 종류로 계산한 확신 등급의 <strong>이름 문자열</strong>이며 없으면 {@code null}
   *     (S15P11B209-982). AI 쪽 코드(LLM 이 아니다)가 계산해 싣는 optional 필드다 — <strong>여기에 Bean Validation 을
   *     붙이면 안 된다.</strong> {@code RestClientAiObservationClient.generate()}가 응답에 {@code
   *     validator.validate(response)}를 돌리므로 어노테이션 하나가 곧 리포트 전체 실패다(2026-08-05 관찰 요청 100% 422 장애).
   *     값이 없거나 해석되지 않으면 "등급 없음"으로 내려앉는 것이 정상이다
   */
  public record PublicInterpretationDraft(
      String category,
      String title,
      String tendencyText,
      String scopeText,
      String homeObservationGuide,
      List<Long> evidenceRefs,
      String confidence) {

    /**
     * 참조 목록이 {@code null}로 와도 빈 목록으로 정규화한다.
     *
     * <p>{@code confidence}는 손대지 않는다 — {@code null}이 "등급 없음"이라는 유효한 값이므로 여기서 기본값을 채우면 등급이 없다는 사실
     * 자체가 사라진다.
     */
    public PublicInterpretationDraft {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 카드가 참조하는 근거 한 건이다 (875 §4).
   *
   * <p>{@code sourceRef}(원본)와 {@code derivedFrom}(파생) 중 <strong>정확히 하나</strong>만 갖는다. 참조 식별자는 서버가
   * 발급한 값이며 조합키는 허용하지 않는다 — 생성자가 만들 수 있는 식별자면 독립 근거 검증이 자기 신고가 된다.
   *
   * @param evidenceId 이 응답 안에서만 유일한 로컬 번호
   * @param sourceType 근거 종류
   * @param text 근거 문장
   * @param sourceRef 원본 참조이며 파생 근거면 {@code null}
   * @param derivedFrom 파생 근거의 원본 참조 목록이며 원본 근거면 빈 목록
   * @param sttNeedsConfirmation 음성 인식 확인이 필요한 발화에서 온 근거인지 여부
   */
  public record EvidenceItemDraft(
      Long evidenceId,
      String sourceType,
      String text,
      EvidenceSourceRefDraft sourceRef,
      List<EvidenceSourceRefDraft> derivedFrom,
      boolean sttNeedsConfirmation) {

    /** 파생 목록이 {@code null}로 와도 빈 목록으로 정규화한다. */
    public EvidenceItemDraft {
      derivedFrom = derivedFrom == null ? List.of() : List.copyOf(derivedFrom);
    }
  }

  /**
   * 원본 근거를 가리키는 참조다.
   *
   * @param kind 원본 근거의 종류
   * @param id 서버가 발급한 식별자
   */
  public record EvidenceSourceRefDraft(String kind, String id) {}

  /**
   * 유형별 보호자 가이드다 (875 §7).
   *
   * <p>{@code PROFESSIONAL_SUPPORT}는 상시 노출되는 일반 상담 안내이며 위기 문구·긴급 연락처를 담지 않는다.
   *
   * @param guideType 가이드 유형
   * @param items 유형 안의 문장 목록
   */
  public record ParentGuideDraft(String guideType, List<String> items) {

    /** 문장 목록이 {@code null}로 와도 빈 목록으로 정규화한다. */
    public ParentGuideDraft {
      items = items == null ? List.of() : List.copyOf(items);
    }
  }

  /**
   * 위기 대응 안내다 (875 §7-1). 보호자 가이드와 다른 필드이며 전부 사전 검토 템플릿이다.
   *
   * @param reasonCode 위기 사유 코드
   * @param severity 심각도
   * @param title 안내 제목
   * @param message 안내 본문
   * @param actionSteps 보호자가 취할 행동 목록
   * @param resources 상담·신고 자원 목록
   */
  public record CrisisAlertDraft(
      String reasonCode,
      String severity,
      String title,
      String message,
      List<String> actionSteps,
      List<CrisisResourceDraft> resources) {

    /** 목록이 {@code null}로 와도 빈 목록으로 정규화한다. */
    public CrisisAlertDraft {
      actionSteps = actionSteps == null ? List.of() : List.copyOf(actionSteps);
      resources = resources == null ? List.of() : List.copyOf(resources);
    }
  }

  /**
   * 위기 안내에 함께 싣는 상담·신고 자원이다.
   *
   * @param name 자원 이름
   * @param contact 연락처
   * @param note 보충 설명이며 없으면 빈 문자열
   */
  public record CrisisResourceDraft(String name, String contact, String note) {}

  // ── 그림일기 V2 구조화 결과 ──────────────────────────────────
  // 한 번의 그림일기를 '주요 심리 경향'으로 만들지 않기 위한 자리다. 경향 카드
  //   (publicInterpretations)는 그림일기에서 AI 가 통째로 비우고, 대신 이 구조가 이번 활동에서
  //   실제로 확인된 것만 담는다.
  // ⚠️ 모든 항목은 AI 가 근거 식별자와 대조해 살아남은 것만 보낸다. BE 는 그 검증을 다시 하지
  //    않지만, 근거가 하나도 없으면 AI 가 diaryInsights 자체를 null 로 보낸다.

  /**
   * 그림일기 한 회차의 구조화 결과다.
   *
   * @param storySnapshot 이번 이야기의 핵심이며 없으면 {@code null}
   * @param narrativeFlow 사건 → 아이 행동 → 상대 반응 → 감정 → 바람 → 결과 순으로 확인된 단계만
   * @param childVoiceItems 아이가 실제로 한 말과 그 말을 끌어낸 질문 방식
   * @param sessionObservations 이번 활동에서만 확인된 표현이며 0~2개다
   * @param caregiverQuestions 보호자가 그대로 이어 물을 수 있는 질문이며 0~2개다
   * @param listeningTip 이번 이야기를 들을 때의 태도 한 문장이며 없으면 {@code null}
   * @param developmentalObservations 연령 발달 맥락과 이번 활동 관찰을 짝지은 항목이다. AI 서버가 검수 등록부와 아이 나이로 정하며
   *     <strong>LLM 이 만들지 않는다</strong> — 맡기면 '또래보다 빠르다'가 곧바로 나온다
   * @param unknownItems 이번 활동에서 확인하지 못한 것이다. 서버가 원자료에서 정하며, 침묵 대신 이름을 돌려주기 위한 자리다 — 비어 나가면 보호자는
   *     '문제가 없었다'로 읽는다
   * @param dataQuality 근거가 무엇으로 이루어졌는지 알려 주는 구성 정보
   */
  public record DiaryInsightsDraft(
      DiaryStorySnapshotDraft storySnapshot,
      List<DiaryNarrativeStepDraft> narrativeFlow,
      List<DiaryChildVoiceItemDraft> childVoiceItems,
      List<DiarySessionObservationDraft> sessionObservations,
      List<DiaryCaregiverQuestionDraft> caregiverQuestions,
      String listeningTip,
      List<DiaryDevelopmentalObservationDraft> developmentalObservations,
      List<DiaryUnknownItemDraft> unknownItems,
      DiaryDataQualityDraft dataQuality) {

    /** 목록은 빈 목록으로 정규화한다. 배열이 비는 것은 '그 섹션을 숨긴다'는 정상 신호다. */
    public DiaryInsightsDraft {
      narrativeFlow = narrativeFlow == null ? List.of() : List.copyOf(narrativeFlow);
      childVoiceItems = childVoiceItems == null ? List.of() : List.copyOf(childVoiceItems);
      sessionObservations =
          sessionObservations == null ? List.of() : List.copyOf(sessionObservations);
      caregiverQuestions = caregiverQuestions == null ? List.of() : List.copyOf(caregiverQuestions);
      developmentalObservations =
          developmentalObservations == null ? List.of() : List.copyOf(developmentalObservations);
    }
  }

  /**
   * 이번 그림일기의 핵심 이야기다.
   *
   * @param headline 이야기의 핵심을 짧게 적은 제목
   * @param summary 사건·아이 행동·상대 반응을 이은 요약
   * @param realityStatus 실제({@code REAL})·상상({@code IMAGINED})·혼합({@code MIXED})·알 수 없음({@code
   *     UNKNOWN})이며 <strong>아이가 말한 경우에만</strong> UNKNOWN 밖의 값이 온다
   * @param timeScope 사건 시점이며 아이가 말하지 않았으면 {@code UNKNOWN}이다. 활동 날짜는 사건 날짜의 근거가 아니다
   * @param mainEvent 중심 사건이며 분명하지 않으면 {@code null}
   * @param evidenceRefs 이 요약을 뒷받침하는 근거 식별자
   */
  public record DiaryStorySnapshotDraft(
      String headline,
      String summary,
      String realityStatus,
      String timeScope,
      String mainEvent,
      List<DiaryEvidenceRefDraft> evidenceRefs) {

    /** 근거 목록은 빈 목록으로 정규화한다. */
    public DiaryStorySnapshotDraft {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 이야기 흐름의 한 단계다.
   *
   * @param stepType {@code EVENT}·{@code CHILD_ACTION}·{@code OTHER_RESPONSE}·{@code
   *     EMOTION}·{@code WISH}·{@code OUTCOME} 중 하나
   * @param text 그 단계에서 확인된 내용
   * @param evidenceRefs 이 단계를 뒷받침하는 근거 식별자
   */
  public record DiaryNarrativeStepDraft(
      String stepType, String text, List<DiaryEvidenceRefDraft> evidenceRefs) {

    /** 근거 목록은 빈 목록으로 정규화한다. */
    public DiaryNarrativeStepDraft {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 아이가 실제로 한 말 한 건이다.
   *
   * @param text 아이가 한 말 그대로
   * @param elicitationType 그 말을 끌어낸 질문 방식이다. {@code OPEN_INVITATION}(열린 질문에 자기 말로)부터 {@code
   *     MULTIPLE_CHOICE}(선택지에서 고름)까지 있으며, <strong>고른 답을 자발 표현처럼 읽지 않기 위한 구분</strong>이다
   * @param answerType 답변 입력 방식이며 없으면 {@code null}
   * @param sourceRef 이 발화의 근거 식별자이며 없으면 {@code null}
   * @param sttNeedsConfirmation 음성 인식 확인이 필요한 답이면 {@code true}. 인용·해석 근거로 쓰지 않는다
   */
  public record DiaryChildVoiceItemDraft(
      String text,
      String elicitationType,
      String answerType,
      DiaryEvidenceRefDraft sourceRef,
      boolean sttNeedsConfirmation) {}

  /**
   * 이번 활동에서 확인된 표현 한 건이다. '심리 경향'이 아니라 <strong>이번 회차에 한정된 관찰</strong>이다.
   *
   * @param observationCode 관찰 코드
   * @param insightType 주장의 세기다. {@code CONFIRMED_EXPRESSION}(아이가 한 말)·{@code SESSION_HYPOTHESIS}(다른
   *     설명이 있어야 성립)·{@code EXPLORE_NEXT}(뜻을 정하지 않은 단서)
   * @param domain 인사이트 영역
   * @param title 보호자에게 보이는 제목
   * @param description 근거에 묶인 이번 활동 한정 설명
   * @param hypothesis 이번 회차 한정 가설이며 없으면 {@code null}
   * @param alternativeExplanations 다르게 볼 수 있는 설명이다. <strong>가설의 필수 짝</strong>이라 비면 AI 가 애초에 가설 카드를
   *     만들지 않는다 — 하나의 해석만 남으면 결론으로 읽힌다
   * @param clarificationQuestion 다음에 확인할 질문이며 {@code EXPLORE_NEXT} 에는 반드시 있다
   * @param scopeText 범위를 알리는 문구이며 화면에 함께 나간다
   * @param evidenceRefs 근거 식별자
   */
  public record DiarySessionObservationDraft(
      String observationCode,
      String insightType,
      String domain,
      String title,
      String description,
      String hypothesis,
      List<String> alternativeExplanations,
      String clarificationQuestion,
      String scopeText,
      List<DiaryEvidenceRefDraft> evidenceRefs) {

    /** 목록은 빈 목록으로 정규화한다. */
    public DiarySessionObservationDraft {
      alternativeExplanations =
          alternativeExplanations == null ? List.of() : List.copyOf(alternativeExplanations);
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 보호자가 아이에게 그대로 물어볼 수 있는 질문이다.
   *
   * @param question 질문 한 문장
   * @param purpose 이 질문으로 더 들어볼 내용
   * @param evidenceRefs 이 질문이 이어지는 근거 식별자
   */
  public record DiaryCaregiverQuestionDraft(
      String question, String purpose, List<DiaryEvidenceRefDraft> evidenceRefs) {

    /** 근거 목록은 빈 목록으로 정규화한다. */
    public DiaryCaregiverQuestionDraft {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 이번 리포트의 근거가 무엇으로 이루어졌는지 알려 준다. 보호자가 '무엇을 근거로 한 이야기인지' 가늠하게 하는 값이다.
   *
   * @param confirmedVoiceCount 음성으로 확정된 답변 수
   * @param optionAnswerCount 선택지에서 고른 답변 수
   * @param skippedCount 건너뛴 질문 수
   * @param sttConfirmationCount 음성 인식 확인이 필요한 답변 수
   * @param evidenceCount 사용된 근거 수
   * @param visionSummaryAvailable 그림 관찰 서술이 있었으면 {@code true}
   */
  public record DiaryDataQualityDraft(
      int confirmedVoiceCount,
      int optionAnswerCount,
      int skippedCount,
      int sttConfirmationCount,
      int evidenceCount,
      boolean visionSummaryAvailable) {}

  /**
   * 구조화 항목이 가리키는 근거 식별자다.
   *
   * @param kind 근거 종류(예: {@code QA_ANSWER})
   * @param id BE 가 발급한 식별자 그대로
   */
  public record DiaryEvidenceRefDraft(String kind, String id) {}

  /**
   * 연령 발달 맥락 관찰 한 건이다.
   *
   * <p>세 조각이 한 항목에 함께 있는 것이 요점이다 — <strong>연령 맥락 → 이번 활동 관찰 → 범위 고지.</strong> 맥락만 보내면 규준 설명이 되고,
   * 관찰만 보내면 무슨 뜻인지 알 수 없으며, 범위 고지가 빠지면 한 회차가 발달 평가로 읽힌다.
   *
   * @param domain {@code NARRATIVE_LANGUAGE}·{@code EMOTION_EXPRESSION}·{@code
   *     SOCIAL_UNDERSTANDING}·{@code COPING_HELP_SEEKING}·{@code SELF_REFLECTION}
   * @param status {@code OBSERVED_THIS_SESSION}·{@code PARTIALLY_OBSERVED}·{@code NOT_ASSESSED}.
   *     <strong>{@code NOT_ASSESSED} 는 '확인하지 않았다'이지 '못한다'가 아니다</strong> — 아이의 무응답·건너뜀·짧은 답은 발달 결함이
   *     아니다
   * @param ageContext 검수된 공개 자료에서 온 연령 맥락 한 줄
   * @param observation 이번 활동에서 확인된 표현
   * @param scopeText 범위 고지이며 화면에 항상 함께 나간다
   * @param sourceIds 검수 출처 식별자다. <strong>비는 것이 정상이다</strong> — 나이를 모르거나 그 도메인에 검수된 한국 규준이 없으면 AI 는
   *     규준 대신 '이번 활동에서만 살펴본다'는 문장을 보내고, 그 문장은 규준을 주장하지 않아 출처가 없다
   * @param evidenceRefs 이번 활동 관찰의 근거 식별자
   */
  public record DiaryDevelopmentalObservationDraft(
      String domain,
      String status,
      String ageContext,
      String observation,
      String scopeText,
      List<String> sourceIds,
      List<DiaryEvidenceRefDraft> evidenceRefs) {

    /** 목록은 빈 목록으로 정규화한다. */
    public DiaryDevelopmentalObservationDraft {
      sourceIds = sourceIds == null ? List.of() : List.copyOf(sourceIds);
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 이번 활동에서 확인하지 못한 것 한 건이다.
   *
   * <p>근거가 없어 카드를 비우면 보호자에게는 '문제가 없었다'로 읽힌다. 침묵 대신 무엇을 알 수 없었는지 이름을 붙여 돌려주는 자리다. 코드와 문구를 <strong>AI
   * 가 원자료에서 정한다</strong> — 모델에게 맡기면 '모르는 것'조차 지어낸다.
   *
   * @param code 서버가 정한 코드
   * @param text 보호자에게 보이는 문구
   */
  public record DiaryUnknownItemDraft(String code, String text) {}
}
