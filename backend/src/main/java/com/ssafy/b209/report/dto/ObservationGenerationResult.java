package com.ssafy.b209.report.dto;

import java.math.BigDecimal;
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
 * @param observationDraft 전문가 검토 전 관찰 초안
 * @param conversationSummary 대화 요약 초안
 * @param activityNotes 객관적 활동 주의사항 목록
 * @param followUpGuides 보호자 후속 안내 목록
 * @param guardianQuestions 보호자 질문 목록
 * @param limitationsText 리포트 해석 한계 문구
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
    String limitationsText) {

  /**
   * 전문가 검토 전 관찰 초안이다.
   *
   * @param status 검토 상태이며 초안은 {@code AI_DRAFT}
   * @param overallSummary 보호자에게 노출 가능한 전체 관찰 요약
   * @param positiveSignals 관찰된 긍정 신호
   * @param attentionPoints 전문가 내부 검토용 관찰 필요 지점
   * @param evidenceSummary 관찰 근거 요약
   * @param guardianGuidance 보호자 안내 문구
   * @param followUpQuestion 보호자가 활용할 후속 질문
   * @param expertReviewRequired 전문가 검토 필요 여부
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
   * @param visibilityScope 노출 범위이며 {@code EXPERT_ONLY} 또는 {@code REVIEWED_GUARDIAN}
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
}
