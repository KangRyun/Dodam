package com.ssafy.b209.analysis.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * 최종 분석에 대한 AI 관찰 결과 초안을 저장한다.
 *
 * <p>보호자에게 바로 노출하면 안 되는 {@code attentionPoints}는 전문가 내부 검토용 컬럼으로만 저장하며, 진단형 표현 없이 관찰 문구와 주의 문구만
 * 담는다.
 */
@Entity
@Table(name = "analysis_observation_results")
public class AnalysisObservationResult {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  @Column(name = "observation_result_id")
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "analysis_id", nullable = false)
  private DrawingAnalysis analysis;

  @Column(name = "result_version")
  private Integer resultVersion;

  @Column(name = "overall_summary", columnDefinition = "TEXT")
  private String overallSummary;

  @Column(name = "positive_signals", columnDefinition = "TEXT")
  private String positiveSignals;

  @Column(name = "attention_points", columnDefinition = "TEXT")
  private String attentionPoints;

  @Column(name = "evidence_summary", columnDefinition = "TEXT")
  private String evidenceSummary;

  @Column(name = "guardian_guidance", columnDefinition = "TEXT")
  private String guardianGuidance;

  @Column(name = "follow_up_question", columnDefinition = "TEXT")
  private String followUpQuestion;

  @Column(name = "is_expert_review_required")
  private Boolean expertReviewRequired;

  @Enumerated(EnumType.STRING)
  @Column(name = "review_status", length = 30)
  private ObservationReviewStatus reviewStatus;

  @Column(name = "disclaimer_text", columnDefinition = "TEXT")
  private String disclaimerText;

  @Column(name = "generated_model_version", length = 255)
  private String generatedModelVersion;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected AnalysisObservationResult() {}

  private AnalysisObservationResult(
      DrawingAnalysis analysis,
      int resultVersion,
      String overallSummary,
      String positiveSignals,
      String attentionPoints,
      String evidenceSummary,
      String guardianGuidance,
      String followUpQuestion,
      boolean expertReviewRequired,
      ObservationReviewStatus reviewStatus,
      String disclaimerText,
      String generatedModelVersion,
      LocalDateTime createdAt) {
    this.analysis = Objects.requireNonNull(analysis, "analysis must not be null");
    if (resultVersion <= 0) {
      throw new IllegalArgumentException("resultVersion must be positive");
    }
    this.resultVersion = resultVersion;
    this.overallSummary = overallSummary;
    this.positiveSignals = positiveSignals;
    this.attentionPoints = attentionPoints;
    this.evidenceSummary = evidenceSummary;
    this.guardianGuidance = guardianGuidance;
    this.followUpQuestion = followUpQuestion;
    this.expertReviewRequired = expertReviewRequired;
    this.reviewStatus = Objects.requireNonNull(reviewStatus, "reviewStatus must not be null");
    this.disclaimerText = requireText(disclaimerText, "disclaimerText");
    this.generatedModelVersion = generatedModelVersion;
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
  }

  /**
   * 전문가 검토 전 AI 초안 관찰 결과를 생성한다.
   *
   * @param analysis 관찰 결과가 속한 최종 분석
   * @param resultVersion 1부터 시작하는 관찰 결과 버전
   * @param overallSummary 보호자에게 노출 가능한 전체 관찰 요약
   * @param positiveSignals 관찰된 긍정 신호
   * @param attentionPoints 전문가 내부 검토용 관찰 필요 지점
   * @param evidenceSummary 관찰 근거 요약
   * @param guardianGuidance 보호자 안내 문구
   * @param followUpQuestion 보호자가 활용할 후속 질문
   * @param expertReviewRequired 사람 상담 권유가 필요한 신호가 잡혔는지 여부
   * @param disclaimerText 진단이 아님을 알리는 필수 주의 문구
   * @param generatedModelVersion 관찰 결과를 생성한 Model 버전
   * @param createdAt 서버가 결과를 저장한 UTC 시각
   * @return 검토 상태가 {@link ObservationReviewStatus#AI_DRAFT}인 관찰 결과
   * @throws IllegalArgumentException 필수 값이 비었거나 버전이 양수가 아닌 경우
   */
  public static AnalysisObservationResult aiDraft(
      DrawingAnalysis analysis,
      int resultVersion,
      String overallSummary,
      String positiveSignals,
      String attentionPoints,
      String evidenceSummary,
      String guardianGuidance,
      String followUpQuestion,
      boolean expertReviewRequired,
      String disclaimerText,
      String generatedModelVersion,
      LocalDateTime createdAt) {
    return of(
        analysis,
        resultVersion,
        overallSummary,
        positiveSignals,
        attentionPoints,
        evidenceSummary,
        guardianGuidance,
        followUpQuestion,
        expertReviewRequired,
        ObservationReviewStatus.AI_DRAFT,
        disclaimerText,
        generatedModelVersion,
        createdAt);
  }

  /**
   * AI 가 실어 보낸 검토 상태 그대로 관찰 결과를 생성한다.
   *
   * <p>{@link #aiDraft}와 달리 검토 상태를 호출부가 정한다. AI 자체 검토를 통과한 결과({@link
   * ObservationReviewStatus#AI_REVIEWED})만 관찰 특징이 보호자에게 열리므로, 이 값은 <b>AI 응답에서만</b> 와야 하고 서버가 임의로
   * 올려서는 안 된다. 해석 불가능한 값을 초안으로 떨어뜨리는 책임은 {@link ObservationReviewStatus#fromAiStatus(String)}에 있다.
   *
   * @param analysis 관찰 결과가 속한 최종 분석
   * @param resultVersion 1부터 시작하는 관찰 결과 버전
   * @param overallSummary 보호자에게 노출 가능한 전체 관찰 요약
   * @param positiveSignals 관찰된 긍정 신호
   * @param attentionPoints 보호자에게 바로 노출하지 않는 내부 검토용 관찰 필요 지점
   * @param evidenceSummary 관찰 근거 요약
   * @param guardianGuidance 보호자 안내 문구
   * @param followUpQuestion 보호자가 활용할 후속 질문
   * @param expertReviewRequired 사람 상담 권유가 필요한 신호가 잡혔는지 여부
   * @param reviewStatus 검토 상태
   * @param disclaimerText 진단이 아님을 알리는 필수 주의 문구
   * @param generatedModelVersion 관찰 결과를 생성한 Model 버전
   * @param createdAt 서버가 결과를 저장한 UTC 시각
   * @return 저장 가능한 관찰 결과
   * @throws IllegalArgumentException 필수 값이 비었거나 버전이 양수가 아닌 경우
   */
  public static AnalysisObservationResult of(
      DrawingAnalysis analysis,
      int resultVersion,
      String overallSummary,
      String positiveSignals,
      String attentionPoints,
      String evidenceSummary,
      String guardianGuidance,
      String followUpQuestion,
      boolean expertReviewRequired,
      ObservationReviewStatus reviewStatus,
      String disclaimerText,
      String generatedModelVersion,
      LocalDateTime createdAt) {
    return new AnalysisObservationResult(
        analysis,
        resultVersion,
        overallSummary,
        positiveSignals,
        attentionPoints,
        evidenceSummary,
        guardianGuidance,
        followUpQuestion,
        expertReviewRequired,
        reviewStatus,
        disclaimerText,
        generatedModelVersion,
        createdAt);
  }

  /**
   * @return 관찰 결과 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 관찰 결과가 속한 최종 분석
   */
  public DrawingAnalysis getAnalysis() {
    return analysis;
  }

  /**
   * @return 관찰 결과 버전
   */
  public Integer getResultVersion() {
    return resultVersion;
  }

  /**
   * @return 보호자에게 노출 가능한 전체 관찰 요약
   */
  public String getOverallSummary() {
    return overallSummary;
  }

  /**
   * @return 관찰된 긍정 신호
   */
  public String getPositiveSignals() {
    return positiveSignals;
  }

  /**
   * @return 전문가 내부 검토용 관찰 필요 지점
   */
  public String getAttentionPoints() {
    return attentionPoints;
  }

  /**
   * @return 관찰 근거 요약
   */
  public String getEvidenceSummary() {
    return evidenceSummary;
  }

  /**
   * @return 보호자 안내 문구
   */
  public String getGuardianGuidance() {
    return guardianGuidance;
  }

  /**
   * @return 보호자가 활용할 후속 질문
   */
  public String getFollowUpQuestion() {
    return followUpQuestion;
  }

  /**
   * 사람 상담 권유가 필요한 신호가 잡혔는지를 돌려준다.
   *
   * <p><b>의미가 재정의된 값이다.</b> 사람 전문가 검토 워크플로가 없으므로 "전문가가 이 리포트를 검토해야 한다"는 뜻이 아니다 — 그런 대기열은 존재하지 않는다.
   * 이 값이 참이면 보호자에게 <b>사람 상담을 권유하는 경로</b>로 이어져야 한다는 신호다. 노출 판정({@link #getReviewStatus()})과는 별개의
   * 축이다.
   *
   * @return 사람 상담 권유가 필요한 신호가 잡혔으면 {@code true}
   */
  public Boolean getExpertReviewRequired() {
    return expertReviewRequired;
  }

  /**
   * @return 현재 검토 상태
   */
  public ObservationReviewStatus getReviewStatus() {
    return reviewStatus;
  }

  /**
   * @return 진단이 아님을 알리는 주의 문구
   */
  public String getDisclaimerText() {
    return disclaimerText;
  }

  /**
   * @return 관찰 결과를 생성한 Model 버전
   */
  public String getGeneratedModelVersion() {
    return generatedModelVersion;
  }

  /**
   * @return 서버가 결과를 저장한 UTC 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
