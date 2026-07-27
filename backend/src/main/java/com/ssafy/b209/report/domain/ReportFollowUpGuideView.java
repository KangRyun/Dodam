package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code report_follow_up_guides} 한 행을 읽는 읽기 모델이다.
 *
 * <p>보호자 후속 안내 문장과 노출 순서만 읽는다.
 */
@Entity
@Table(name = "report_follow_up_guides")
public class ReportFollowUpGuideView {

  @Id private Long id;

  @Column(name = "report_id", nullable = false)
  private Long reportId;

  @Column(name = "guidance", nullable = false)
  private String guidance;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  protected ReportFollowUpGuideView() {}

  /**
   * @return 후속 안내 식별자
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
   * @return 보호자 안내 문장
   */
  public String getGuidance() {
    return guidance;
  }

  /**
   * @return 노출 순서
   */
  public short getDisplayOrder() {
    return displayOrder;
  }
}
