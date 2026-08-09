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

/** 위기 대응 안내의 행동 단계 한 건이다 (S15P11B209-902). 사전 검토 템플릿의 순서를 그대로 보존한다. */
@Entity
@Table(name = "report_crisis_alert_steps")
public class ReportCrisisAlertStep {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private ReportCrisisAlert crisisAlert;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  @Column(name = "step_text", nullable = false, columnDefinition = "TEXT")
  private String stepText;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportCrisisAlertStep() {}

  private ReportCrisisAlertStep(ReportCrisisAlert crisisAlert, int displayOrder, String stepText) {
    this.crisisAlert = Objects.requireNonNull(crisisAlert, "crisisAlert must not be null");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    if (stepText == null || stepText.isBlank()) {
      throw new IllegalArgumentException("stepText must not be blank");
    }
    this.stepText = stepText;
  }

  /**
   * 행동 단계를 생성한다.
   *
   * @param crisisAlert 단계가 속한 위기 안내
   * @param displayOrder 0부터 시작하는 순서
   * @param stepText 행동 문구
   * @return 저장 가능한 행동 단계
   */
  static ReportCrisisAlertStep create(
      ReportCrisisAlert crisisAlert, int displayOrder, String stepText) {
    return new ReportCrisisAlertStep(crisisAlert, displayOrder, stepText);
  }

  /**
   * @return 0부터 시작하는 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  /**
   * @return 행동 문구
   */
  public String getStepText() {
    return stepText;
  }
}
