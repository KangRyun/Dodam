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
import java.util.Locale;
import java.util.Objects;

/**
 * 주제별 문답 한 쌍이다 (875 §5 {@code qaPairs} / §6).
 *
 * <p><strong>아이 발화 원문을 그대로 담는다.</strong> AI 가 이 값을 만들지 않는 이유가 그것이다(S15P11B209-941) — LLM 을 통과시켜 되돌려
 * 받으면 아이 말이 바뀔 여지만 생기고, 원문 보존이 인용의 전제다.
 *
 * <p><strong>{@code sttNeedsConfirmation}은 표시 규칙이지 삭제 규칙이 아니다</strong>(875 §6-1). {@code true}여도
 * 문답에는 남기고 화면이 "음성 인식 내용을 확인해 주세요"를 함께 보여 준다 — 아이 말을 지우지 않는다. 근거·대표 발화에서만 제외한다.
 */
@Entity
@Table(name = "report_subject_qa_pairs")
public class ReportSubjectQaPair {

  /** 답변한 문답 상태다. */
  public static final String STATE_ANSWERED = "ANSWERED";

  /** 건너뛴 문답 상태다. */
  public static final String STATE_SKIPPED = "SKIPPED";

  /** 문자 입력 방식이다. */
  public static final String INPUT_TEXT = "TEXT";

  /** 음성 입력 방식이다. */
  public static final String INPUT_VOICE = "VOICE";

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_subject_id", nullable = false)
  private ReportSubject subject;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Column(name = "question_text", nullable = false, columnDefinition = "TEXT")
  private String questionText;

  @Column(name = "answer_text", columnDefinition = "TEXT")
  private String answerText;

  @Column(name = "answer_state", nullable = false, length = 20)
  private String answerState;

  @Column(name = "input_type", nullable = false, length = 20)
  private String inputType;

  @Column(name = "stt_needs_confirmation", nullable = false)
  private boolean sttNeedsConfirmation;

  @Column(name = "is_representative", nullable = false)
  private boolean representative;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportSubjectQaPair() {}

  private ReportSubjectQaPair(
      ReportSubject subject,
      int displayOrder,
      String questionText,
      String answerText,
      String answerState,
      String inputType,
      boolean sttNeedsConfirmation,
      boolean representative) {
    this.subject = Objects.requireNonNull(subject, "subject must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    if (questionText == null || questionText.isBlank()) {
      throw new IllegalArgumentException("questionText must not be blank");
    }
    this.questionText = questionText;
    this.answerState = normalizeState(answerState);
    this.inputType = normalizeInputType(inputType);
    // 건너뛴 문답에 답변을 남기면 화면이 "건너뛰었어요"와 답변을 동시에 보여 준다. DB CHECK 와 같은 규칙이다.
    this.answerText =
        STATE_SKIPPED.equals(this.answerState) || answerText == null || answerText.isBlank()
            ? null
            : answerText;
    this.sttNeedsConfirmation = sttNeedsConfirmation;
    this.representative = representative;
  }

  /**
   * 주제에 연결되는 문답 한 쌍을 생성한다.
   *
   * @param subject 문답이 속한 주제별 관찰 묶음
   * @param displayOrder 0부터 시작하는 노출 순서
   * @param questionText 질문 원문
   * @param answerText 답변 원문이며 건너뛰었으면 {@code null}
   * @param answerState 답변 상태이며 모르는 값은 {@code SKIPPED}로 떨어진다
   * @param inputType 입력 방식이며 모르는 값은 {@code TEXT}로 떨어진다
   * @param sttNeedsConfirmation 음성 인식 확인이 필요한 답변인지 여부
   * @param representative 대표 문답인지 여부
   * @return 저장 가능한 문답
   * @throws IllegalArgumentException 순서가 음수이거나 질문이 빈 경우
   */
  public static ReportSubjectQaPair create(
      ReportSubject subject,
      int displayOrder,
      String questionText,
      String answerText,
      String answerState,
      String inputType,
      boolean sttNeedsConfirmation,
      boolean representative) {
    return new ReportSubjectQaPair(
        subject,
        displayOrder,
        questionText,
        answerText,
        answerState,
        inputType,
        sttNeedsConfirmation,
        representative);
  }

  /**
   * @return 문답 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 0부터 시작하는 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  /**
   * @return 질문 원문
   */
  public String getQuestionText() {
    return questionText;
  }

  /**
   * @return 답변 원문이며 건너뛰었으면 {@code null}
   */
  public String getAnswerText() {
    return answerText;
  }

  /**
   * @return 답변 상태({@code ANSWERED}·{@code SKIPPED})
   */
  public String getAnswerState() {
    return answerState;
  }

  /**
   * @return 입력 방식({@code TEXT}·{@code VOICE})
   */
  public String getInputType() {
    return inputType;
  }

  /**
   * @return 음성 인식 확인이 필요한 답변인지 여부
   */
  public boolean isSttNeedsConfirmation() {
    return sttNeedsConfirmation;
  }

  /**
   * @return 대표 문답인지 여부
   */
  public boolean isRepresentative() {
    return representative;
  }

  /** 모르는 상태는 {@code SKIPPED}로 떨어뜨린다 — 답하지 않은 것으로 보는 쪽이 없는 답을 지어내지 않는다. */
  private static String normalizeState(String value) {
    if (value == null) {
      return STATE_SKIPPED;
    }
    String normalized = value.trim().toUpperCase(Locale.ROOT);
    return STATE_ANSWERED.equals(normalized) ? STATE_ANSWERED : STATE_SKIPPED;
  }

  /** 음성으로 확인되지 않으면 문자 입력으로 본다. 오분류가 "확인해 주세요" 문구를 잘못 띄우지 않게 한다. */
  private static String normalizeInputType(String value) {
    if (value == null) {
      return INPUT_TEXT;
    }
    return value.trim().toUpperCase(Locale.ROOT).contains(INPUT_VOICE) ? INPUT_VOICE : INPUT_TEXT;
  }
}
