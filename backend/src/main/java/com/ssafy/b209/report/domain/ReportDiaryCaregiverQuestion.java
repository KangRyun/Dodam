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
 * 그림일기 V2 "오늘 마음 나누기" 교감 카드다. 보호자가 아이와 정서적 교감을 나누도록, 아이에게 그대로 물을 감정 앵커 질문과 함께 아이 답에
 * 부모가 어떻게 마음으로 반응할지({@code responseGuide})를 담는다.
 *
 * <p>{@link ReportFollowUpGuide} 와 다르다. 저쪽은 듣는 태도 안내까지 담는 자리고, 여기는 <strong>아이가 실제로 말한 사건·행동·관계에 직접
 * 이어지는 질문</strong>만 담는다. "더 이야기해 보세요" 같은 일반론은 근거가 없어 여기 오지 못한다.
 *
 * <p>{@code responseGuide}·{@code coRegulationAction} 은 <strong>AI 서버가 {@code connectionType} 으로 정적 매핑</strong>한 값이다 —
 * LLM 이 만들지 않는다. 공감 문구를 모델에게 맡기면 발달 규준 주장이나 지시형 훈육으로 새기 쉬워서다.
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

  @Column(name = "connection_type", nullable = false, length = 30)
  private String connectionType;

  @Column(name = "response_guide", columnDefinition = "TEXT")
  private String responseGuide;

  @Column(name = "co_regulation_action", columnDefinition = "TEXT")
  private String coRegulationAction;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryCaregiverQuestion() {}

  private ReportDiaryCaregiverQuestion(
      Report report,
      String question,
      String purpose,
      String connectionType,
      String responseGuide,
      String coRegulationAction,
      int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.question = Objects.requireNonNull(question, "question must not be null");
    this.purpose = purpose;
    this.connectionType =
        Objects.requireNonNull(connectionType, "connectionType must not be null");
    this.responseGuide = responseGuide;
    this.coRegulationAction = coRegulationAction;
    this.displayOrder = displayOrder;
  }

  /**
   * "오늘 마음 나누기" 교감 카드를 만든다.
   *
   * @param report 소속 리포트
   * @param question 보호자가 그대로 물어볼 감정 앵커 질문
   * @param purpose 이 질문으로 더 들어볼 내용이며 없으면 {@code null}
   * @param connectionType 교감 유형({@code FEELING_SHARING}·{@code COMFORT_SEEKING}·{@code SHARED_JOY}·{@code
   *     PERSPECTIVE_TAKING}·{@code GENERAL_CONNECTION})
   * @param responseGuide 아이 답에 부모가 마음으로 반응하는 법이며 서버가 유형으로 정적 매핑한다. 없으면 {@code null}
   * @param coRegulationAction 함께 해보기 한 줄이며 없으면 {@code null}
   * @param displayOrder 노출 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryCaregiverQuestion create(
      Report report,
      String question,
      String purpose,
      String connectionType,
      String responseGuide,
      String coRegulationAction,
      int displayOrder) {
    return new ReportDiaryCaregiverQuestion(
        report, question, purpose, connectionType, responseGuide, coRegulationAction, displayOrder);
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
   * @return 교감 유형
   */
  public String getConnectionType() {
    return connectionType;
  }

  /**
   * @return 아이 답에 부모가 마음으로 반응하는 법이며 없으면 {@code null}
   */
  public String getResponseGuide() {
    return responseGuide;
  }

  /**
   * @return 함께 해보기 한 줄이며 없으면 {@code null}
   */
  public String getCoRegulationAction() {
    return coRegulationAction;
  }

  /**
   * @return 노출 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
