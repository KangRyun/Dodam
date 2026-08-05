package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code report_observed_features} 한 행을 읽는 읽기 모델이다.
 *
 * <p><b>노출 범위 컬럼을 함께 읽는 이유</b>는 조회 자체를 {@link ReportFeatureVisibility#REVIEWED_GUARDIAN} 로 제한하기
 * 위해서다. 전부 읽고 서비스에서 걸러내면 {@link ReportFeatureVisibility#EXPERT_ONLY} 문구가 응답 조립 코드까지 흘러 들어와, 다음 사람이
 * 실수로 담을 여지가 생긴다. 보호자에게 열리지 않는 데이터는 <b>애초에 조회하지 않는다.</b>
 */
@Entity
@Table(name = "report_observed_features")
public class ReportObservedFeatureView {

  @Id private Long id;

  @Column(name = "report_id", nullable = false)
  private Long reportId;

  @Column(name = "title")
  private String title;

  @Column(name = "description", nullable = false)
  private String description;

  @Column(name = "evidence_summary")
  private String evidenceSummary;

  @Enumerated(EnumType.STRING)
  @Column(name = "visibility_scope", nullable = false)
  private ReportFeatureVisibility visibilityScope;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  protected ReportObservedFeatureView() {}

  /**
   * @return 관찰 특징 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 리포트 식별자
   */
  public Long getReportId() {
    return reportId;
  }

  /**
   * @return 관찰 제목이며 없으면 {@code null}
   */
  public String getTitle() {
    return title;
  }

  /**
   * @return 관찰 내용
   */
  public String getDescription() {
    return description;
  }

  /**
   * @return 관찰 근거 요약이며 없으면 {@code null}
   */
  public String getEvidenceSummary() {
    return evidenceSummary;
  }

  /**
   * @return 노출 범위
   */
  public ReportFeatureVisibility getVisibilityScope() {
    return visibilityScope;
  }

  /**
   * @return 노출 순서
   */
  public short getDisplayOrder() {
    return displayOrder;
  }
}
