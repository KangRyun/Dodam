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
 * 리포트에 노출할 대표 질문·답변 쌍의 Snapshot을 저장한다.
 *
 * <p>원본 대화 메시지 식별자는 참조로만 보관하고, 노출 문구는 Snapshot으로 저장해 원본 변경과 분리한다.
 */
@Entity
@Table(name = "report_key_conversations")
public class ReportKeyConversation {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "question_message_id")
  private Long questionMessageId;

  @Column(name = "answer_message_id")
  private Long answerMessageId;

  @Column(name = "question_text", nullable = false, columnDefinition = "TEXT")
  private String questionText;

  @Column(name = "answer_text", columnDefinition = "TEXT")
  private String answerText;

  @Column(name = "answer_type", length = 30)
  private String answerType;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportKeyConversation() {}

  private ReportKeyConversation(
      Report report,
      Long questionMessageId,
      Long answerMessageId,
      String questionText,
      String answerText,
      String answerType,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.questionMessageId = questionMessageId;
    this.answerMessageId = answerMessageId;
    this.questionText = requireText(questionText, "questionText");
    this.answerText = answerText;
    this.answerType = answerType;
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
  }

  /**
   * 리포트에 연결되는 대표 대화 Snapshot을 생성한다.
   *
   * @param report 대화가 속한 리포트
   * @param questionMessageId 원본 질문 메시지 식별자이며 없으면 {@code null}
   * @param answerMessageId 원본 답변 메시지 식별자이며 없으면 {@code null}
   * @param questionText 질문 Snapshot
   * @param answerText 답변 Snapshot이며 없으면 {@code null}
   * @param answerType 답변 유형 Snapshot이며 없으면 {@code null}
   * @param displayOrder 0부터 시작하는 노출 순서
   * @return 저장 가능한 대표 대화 Snapshot
   * @throws IllegalArgumentException 질문 Snapshot이 비었거나 순서가 음수인 경우
   */
  public static ReportKeyConversation create(
      Report report,
      Long questionMessageId,
      Long answerMessageId,
      String questionText,
      String answerText,
      String answerType,
      int displayOrder) {
    return new ReportKeyConversation(
        report,
        questionMessageId,
        answerMessageId,
        questionText,
        answerText,
        answerType,
        displayOrder);
  }

  /**
   * @return 대표 대화 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 원본 질문 메시지 식별자이며 없으면 {@code null}
   */
  public Long getQuestionMessageId() {
    return questionMessageId;
  }

  /**
   * @return 원본 답변 메시지 식별자이며 없으면 {@code null}
   */
  public Long getAnswerMessageId() {
    return answerMessageId;
  }

  /**
   * @return 질문 Snapshot
   */
  public String getQuestionText() {
    return questionText;
  }

  /**
   * @return 답변 Snapshot이며 없으면 {@code null}
   */
  public String getAnswerText() {
    return answerText;
  }

  /**
   * @return 답변 유형 Snapshot이며 없으면 {@code null}
   */
  public String getAnswerType() {
    return answerType;
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
