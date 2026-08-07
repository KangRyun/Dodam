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
 * 그림일기 V2 에서 보호자가 아이에게 그대로 이어 물을 수 있는 질문이다.
 *
 * <p>{@link ReportFollowUpGuide} 와 다르다. 저쪽은 듣는 태도 안내까지 담는 자리고, 여기는 <strong>아이가 실제로 말한 사건·행동·관계에 직접
 * 이어지는 질문</strong>만 담는다. "더 이야기해 보세요" 같은 일반론은 근거가 없어 여기 오지 못한다.
 */
@Entity
@Table(name = "report_diary_caregiver_questions")
public class ReportDiaryCaregiverQuestion {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "question", nullable = false, columnDefinition = "TEXT")
  private String question;

  @Column(name = "purpose", length = 300)
  private String purpose;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryCaregiverQuestion() {}

  private ReportDiaryCaregiverQuestion(
      Report report, String question, String purpose, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.question = Objects.requireNonNull(question, "question must not be null");
    this.purpose = purpose;
    this.displayOrder = displayOrder;
  }

  /**
   * 보호자 질문을 만든다.
   *
   * @param report 소속 리포트
   * @param question 보호자가 그대로 물어볼 질문
   * @param purpose 이 질문으로 더 들어볼 내용이며 없으면 {@code null}
   * @param displayOrder 노출 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryCaregiverQuestion create(
      Report report, String question, String purpose, int displayOrder) {
    return new ReportDiaryCaregiverQuestion(report, question, purpose, displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 보호자가 그대로 물어볼 질문
   */
  public String getQuestion() {
    return question;
  }

  /**
   * @return 이 질문으로 더 들어볼 내용이며 없으면 {@code null}
   */
  public String getPurpose() {
    return purpose;
  }

  /**
   * @return 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
