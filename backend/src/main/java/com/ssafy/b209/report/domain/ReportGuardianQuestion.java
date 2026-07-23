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

/** 보호자가 아동과 대화할 때 활용할 질문을 노출 순서와 함께 저장한다. */
@Entity
@Table(name = "report_guardian_questions")
public class ReportGuardianQuestion {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "question_text", nullable = false, columnDefinition = "TEXT")
  private String questionText;

  @Column(name = "question_purpose", length = 50)
  private String questionPurpose;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportGuardianQuestion() {}

  private ReportGuardianQuestion(
      Report report, String questionText, String questionPurpose, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.questionText = requireText(questionText, "questionText");
    this.questionPurpose = questionPurpose;
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
  }

  /**
   * 리포트에 연결되는 보호자 질문을 생성한다.
   *
   * @param report 질문이 속한 리포트
   * @param questionText 보호자 질문 문장
   * @param questionPurpose 질문 목적이며 없으면 {@code null}
   * @param displayOrder 0부터 시작하는 노출 순서
   * @return 저장 가능한 보호자 질문
   * @throws IllegalArgumentException 질문 문장이 비었거나 순서가 음수인 경우
   */
  public static ReportGuardianQuestion create(
      Report report, String questionText, String questionPurpose, int displayOrder) {
    return new ReportGuardianQuestion(report, questionText, questionPurpose, displayOrder);
  }

  /**
   * @return 보호자 질문 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 보호자 질문 문장
   */
  public String getQuestionText() {
    return questionText;
  }

  /**
   * @return 질문 목적이며 없으면 {@code null}
   */
  public String getQuestionPurpose() {
    return questionPurpose;
  }

  /**
   * @return 0부터 시작하는 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
