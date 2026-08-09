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
 * 그림일기 V3에서 이미지로 직접 확인한 사실 한 건을 저장한다.
 *
 * <p>해석이나 진단을 저장하지 않으며, 아이 발화로 다시 확인됐는지를 별도 값으로 보존한다.
 */
@Entity
@Table(name = "report_diary_visual_observations")
public class ReportDiaryVisualObservation {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id", nullable = false)
  private Report report;

  @Column(name = "text", nullable = false, columnDefinition = "TEXT")
  private String text;

  @Column(name = "confidence", nullable = false, length = 20)
  private String confidence;

  @Column(name = "child_confirmed", nullable = false)
  private boolean childConfirmed;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT")
  private int displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportDiaryVisualObservation() {}

  private ReportDiaryVisualObservation(
      Report report, String text, String confidence, boolean childConfirmed, int displayOrder) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.text = Objects.requireNonNull(text, "text must not be null");
    this.confidence = Objects.requireNonNull(confidence, "confidence must not be null");
    this.childConfirmed = childConfirmed;
    this.displayOrder = displayOrder;
  }

  /**
   * 근거 검증을 마친 그림 관찰을 만든다.
   *
   * @param report 소속 리포트
   * @param text 이미지에서 직접 확인한 사실
   * @param confidence 관찰 신뢰 수준
   * @param childConfirmed 아이 발화로도 확인됐는지 여부
   * @param displayOrder 화면 표시 순서
   * @return 저장 대기 Entity
   */
  public static ReportDiaryVisualObservation create(
      Report report, String text, String confidence, boolean childConfirmed, int displayOrder) {
    return new ReportDiaryVisualObservation(report, text, confidence, childConfirmed, displayOrder);
  }

  /**
   * @return 이미지에서 직접 확인한 사실
   */
  public String getText() {
    return text;
  }

  /**
   * @return HIGH·MODERATE·LOW 중 하나
   */
  public String getConfidence() {
    return confidence;
  }

  /**
   * @return 아이 발화로도 확인된 사실이면 {@code true}
   */
  public boolean isChildConfirmed() {
    return childConfirmed;
  }

  /**
   * @return 화면 표시 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
