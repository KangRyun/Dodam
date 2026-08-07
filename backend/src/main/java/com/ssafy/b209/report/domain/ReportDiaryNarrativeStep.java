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
 * 그림일기 V2 이야기 흐름의 한 단계다.
 *
 * <p>사건 → 아이 행동 → 상대 반응 → 감정 → 바람 → 결과 순으로, <strong>확인된 단계만</strong> 담는다. 빠진 단계를 채우지 않는 것이 계약이다 —
 * 채우는 순간 아이가 하지 않은 말이 흐름에 들어간다.
 */
@Entity
@Table(name = "report_diary_narrative_steps")
public class ReportDiaryNarrativeStep {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "step_type", nullable = false, length = 30)
  private String stepType;

  @Column(name = "text", nullable = false, columnDefinition = "TEXT")
  private String text;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryNarrativeStep() {}

  private ReportDiaryNarrativeStep(Report report, String stepType, String text, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.stepType = Objects.requireNonNull(stepType, "stepType must not be null");
    this.text = Objects.requireNonNull(text, "text must not be null");
    this.displayOrder = displayOrder;
  }

  /**
   * 흐름 단계를 만든다.
   *
   * @param report 소속 리포트
   * @param stepType 단계 종류
   * @param text 그 단계에서 확인된 내용
   * @param displayOrder 시간 흐름 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryNarrativeStep create(
      Report report, String stepType, String text, int displayOrder) {
    return new ReportDiaryNarrativeStep(report, stepType, text, displayOrder);
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 단계 종류
   */
  public String getStepType() {
    return stepType;
  }

  /**
   * @return 그 단계에서 확인된 내용
   */
  public String getText() {
    return text;
  }

  /**
   * @return 시간 흐름 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
