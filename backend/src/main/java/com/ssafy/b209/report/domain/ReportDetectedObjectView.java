package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code analysis_detected_objects} 한 행을 읽는 읽기 모델이다.
 *
 * <p>보호자에게는 객체명만 노출한다. 신뢰도는 새 리포트에 노출하지 않고, VLM drawnItems가 없는 과거 리포트의 0.50 폴백 판정에만 사용한다.
 */
@Entity
@Table(name = "analysis_detected_objects")
public class ReportDetectedObjectView {

  @Id
  @Column(name = "detected_object_id")
  private Long id;

  @Column(name = "analysis_id", nullable = false)
  private Long analysisId;

  @Column(name = "object_name")
  private String objectName;

  @Column(name = "detection_order")
  private Integer detectionOrder;

  @Column(name = "confidence_score")
  private java.math.BigDecimal confidenceScore;

  protected ReportDetectedObjectView() {}

  /**
   * @return 탐지 객체 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 탐지 결과가 속한 분석 식별자
   */
  public Long getAnalysisId() {
    return analysisId;
  }

  /**
   * @return 탐지된 객체명이며 없으면 {@code null}
   */
  public String getObjectName() {
    return objectName;
  }

  /**
   * @return 탐지 순서이며 없으면 {@code null}
   */
  public Integer getDetectionOrder() {
    return detectionOrder;
  }
}
