package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code report_activity_notes} 한 행을 읽는 읽기 모델이다.
 *
 * <p>해석을 배제한 객관적 활동 주의사항 문장과 노출 순서만 읽는다.
 */
@Entity
@Table(name = "report_activity_notes")
public class ReportActivityNoteView {

  @Id private Long id;

  @Column(name = "report_id", nullable = false)
  private Long reportId;

  @Column(name = "note_text", nullable = false)
  private String noteText;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  protected ReportActivityNoteView() {}

  /**
   * @return 활동 주의사항 식별자
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
   * @return 객관적 활동 주의사항 문장
   */
  public String getNoteText() {
    return noteText;
  }

  /**
   * @return 노출 순서
   */
  public short getDisplayOrder() {
    return displayOrder;
  }
}
