package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code analysis_detected_objects} 한 행을 읽는 읽기 모델이다.
 *
 * <p>보호자에게는 객관적 사실인 탐지 객체명과 탐지 순서만 읽어 노출하며, 신뢰도 점수나 좌표 등 해석성 수치는 읽지 않는다.
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
