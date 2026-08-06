package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code reports} 한 행을 읽는 읽기 모델이다.
 *
 * <p>리포트 생성 책임을 가진 {@link Report}와 같은 테이블을 별도 경계로 매핑해 조회에 필요한 컬럼만 스칼라로 읽는다. 이 Entity는 상태를 변경하지 않는다.
 */
@Entity
@Table(name = "reports")
public class ReportDetailView {

  @Id private Long id;

  @Column(name = "drawing_session_id", nullable = false)
  private Long drawingSessionId;

  @Column(name = "analysis_id", nullable = false)
  private Long analysisId;

  @Column(name = "report_version", nullable = false)
  private int reportVersion;

  @Enumerated(EnumType.STRING)
  @Column(name = "report_status", nullable = false)
  private ReportStatus status;

  @Column(name = "limitations_text", nullable = false)
  private String limitationsText;

  @Column(name = "hidden_at")
  private LocalDateTime hiddenAt;

  @Column(name = "has_drawn_items", nullable = false)
  private boolean hasDrawnItems;

  @Column(name = "ai_raw_report")
  private String aiRawReport;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  protected ReportDetailView() {}

  /**
   * @return 리포트 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 리포트 대상 그림 활동 세션 식별자
   */
  public Long getDrawingSessionId() {
    return drawingSessionId;
  }

  /**
   * @return 리포트 생성 근거가 되는 최종 분석 식별자
   */
  public Long getAnalysisId() {
    return analysisId;
  }

  /**
   * @return 세션 안에서 증가하는 리포트 버전
   */
  public int getReportVersion() {
    return reportVersion;
  }

  /**
   * @return 현재 리포트 생성 상태
   */
  public ReportStatus getStatus() {
    return status;
  }

  /**
   * @return 리포트 해석 시 적용할 한계와 주의 문구
   */
  public String getLimitationsText() {
    return limitationsText;
  }

  /**
   * @return 서버가 리포트 생성을 접수한 UTC 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  /**
   * @return 최신 AI 관찰 서술 기반 drawnItems를 저장한 리포트이면 {@code true}
   */
  public boolean hasDrawnItems() {
    return hasDrawnItems;
  }

  /**
   * 생성 때 보관해 둔 AI 관찰 응답 원문이다 (S15P11B209-980).
   *
   * @return AI 응답 원문이며 보관 이전 리포트나 받아 두지 못한 리포트면 {@code null}
   */
  public String getAiRawReport() {
    return aiRawReport;
  }

  /**
   * 보호자에게 리포트 존재를 노출하지 않아야 하는 숨김 상태인지 판별한다.
   *
   * @return 숨김 처리된 리포트이면 {@code true}
   */
  public boolean isHidden() {
    return status == ReportStatus.HIDDEN || hiddenAt != null;
  }
}
