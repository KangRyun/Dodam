package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.util.Objects;

/**
 * 그림일기 V2 에서 아이가 실제로 한 말 한 건이다.
 *
 * <p>{@code elicitationType} 이 이 Entity 의 핵심이다. "응."(예·아니오)과 "기분이 좋아서 엄마한테 자랑했어"(열린 질문에 자기 말)를 같은
 * 근거로 세면, AI 가 제시한 답을 아이의 자발 표현처럼 기록하게 된다. 그래서 말과 함께 <strong>그 말을 끌어낸 방식</strong>을 남긴다.
 */
@Entity
@Table(name = "report_diary_child_voices")
public class ReportDiaryChildVoice {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "text", nullable = false, columnDefinition = "TEXT")
  private String text;

  @Column(name = "elicitation_type", nullable = false, length = 30)
  private String elicitationType;

  @Column(name = "answer_type", length = 30)
  private String answerType;

  @Column(name = "source_ref_kind", length = 40)
  private String sourceRefKind;

  @Column(name = "source_ref_id", length = 64)
  private String sourceRefId;

  @Column(name = "stt_needs_confirmation", nullable = false)
  private boolean sttNeedsConfirmation;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryChildVoice() {}

  private ReportDiaryChildVoice(
      Report report,
      String text,
      String elicitationType,
      String answerType,
      String sourceRefKind,
      String sourceRefId,
      boolean sttNeedsConfirmation,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.text = Objects.requireNonNull(text, "text must not be null");
    this.elicitationType =
        Objects.requireNonNull(elicitationType, "elicitationType must not be null");
    this.answerType = answerType;
    this.sourceRefKind = sourceRefKind;
    this.sourceRefId = sourceRefId;
    this.sttNeedsConfirmation = sttNeedsConfirmation;
    this.displayOrder = displayOrder;
  }

  /**
   * 아이 발화를 만든다.
   *
   * @param report 소속 리포트
   * @param text 아이가 한 말 그대로
   * @param elicitationType 그 말을 끌어낸 질문 방식
   * @param answerType 답변 입력 방식이며 없으면 {@code null}
   * @param sourceRefKind 근거 종류이며 없으면 {@code null}
   * @param sourceRefId 근거 식별자이며 없으면 {@code null}
   * @param sttNeedsConfirmation 음성 인식 확인이 필요하면 {@code true}
   * @param displayOrder 노출 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryChildVoice create(
      Report report,
      String text,
      String elicitationType,
      String answerType,
      String sourceRefKind,
      String sourceRefId,
      boolean sttNeedsConfirmation,
      int displayOrder) {
    return new ReportDiaryChildVoice(
        report,
        text,
        elicitationType,
        answerType,
        sourceRefKind,
        sourceRefId,
        sttNeedsConfirmation,
        displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 아이가 한 말 그대로
   */
  public String getText() {
    return text;
  }

  /**
   * @return 그 말을 끌어낸 질문 방식
   */
  public String getElicitationType() {
    return elicitationType;
  }

  /**
   * @return 답변 입력 방식이며 없으면 {@code null}
   */
  public String getAnswerType() {
    return answerType;
  }

  /**
   * @return 근거 종류이며 없으면 {@code null}
   */
  public String getSourceRefKind() {
    return sourceRefKind;
  }

  /**
   * @return 근거 식별자이며 없으면 {@code null}
   */
  public String getSourceRefId() {
    return sourceRefId;
  }

  /**
   * @return 음성 인식 확인이 필요하면 {@code true}
   */
  public boolean isSttNeedsConfirmation() {
    return sttNeedsConfirmation;
  }

  /**
   * @return 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
