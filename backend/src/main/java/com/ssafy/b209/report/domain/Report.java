package com.ssafy.b209.report.domain;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.drawing.domain.DrawingSession;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * 그림 활동의 최종 분석을 보호자용 리포트로 생성하는 상태와 버전을 관리한다.
 *
 * <p>정규화된 리포트 상세 내용은 후속 생성 작업이 별도 Table에 저장하며, 이 Entity는 생성 접수와 생명주기만 담당한다.
 */
@Entity
@Table(name = "reports")
public class Report {

  private static final String GENERATING_LIMITATIONS =
      "리포트 생성이 완료되지 않았습니다. 생성 완료 전에는 결과로 해석하지 마세요.";

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_session_id", nullable = false)
  private DrawingSession drawingSession;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "analysis_id", nullable = false)
  private DrawingAnalysis analysis;

  @Column(name = "report_version", nullable = false)
  private int reportVersion;

  @Enumerated(EnumType.STRING)
  @Column(name = "report_status", nullable = false, length = 20)
  private ReportStatus status;

  @Column(name = "is_expert_review_recommended", nullable = false)
  private boolean expertReviewRecommended;

  @Column(name = "limitations_text", nullable = false, columnDefinition = "TEXT")
  private String limitationsText;

  @Enumerated(EnumType.STRING)
  @Column(name = "pdf_status", nullable = false, length = 20)
  private ReportPdfStatus pdfStatus;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected Report() {}

  /**
   * 최종 분석 결과를 기다리는 생성 중 리포트를 만든다.
   *
   * @param drawingSession 리포트 대상 그림 활동 세션
   * @param analysis 리포트 생성 근거가 되는 최종 분석
   * @param reportVersion 세션 안에서 증가하는 양의 리포트 버전
   * @param createdAt 서버가 생성을 접수한 UTC 시각
   * @return 상세 내용과 PDF가 아직 없는 생성 중 리포트
   */
  public static Report generating(
      DrawingSession drawingSession,
      DrawingAnalysis analysis,
      int reportVersion,
      LocalDateTime createdAt) {
    if (reportVersion <= 0) {
      throw new IllegalArgumentException("reportVersion must be positive");
    }
    Report report = new Report();
    report.drawingSession =
        Objects.requireNonNull(drawingSession, "drawingSession must not be null");
    report.analysis = Objects.requireNonNull(analysis, "analysis must not be null");
    report.reportVersion = reportVersion;
    report.status = ReportStatus.GENERATING;
    report.expertReviewRecommended = false;
    report.limitationsText = GENERATING_LIMITATIONS;
    report.pdfStatus = ReportPdfStatus.NONE;
    report.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
    report.updatedAt = createdAt;
    return report;
  }

  /**
   * @return 영속화된 리포트 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 리포트가 속한 그림 활동 세션
   */
  public DrawingSession getDrawingSession() {
    return drawingSession;
  }

  /**
   * @return 리포트 생성 근거가 되는 최종 분석
   */
  public DrawingAnalysis getAnalysis() {
    return analysis;
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
   * @return 전문가 검토 권장 여부
   */
  public boolean isExpertReviewRecommended() {
    return expertReviewRecommended;
  }

  /**
   * @return 리포트 해석 시 적용할 한계와 주의 문구
   */
  public String getLimitationsText() {
    return limitationsText;
  }

  /**
   * @return PDF 생성 상태
   */
  public ReportPdfStatus getPdfStatus() {
    return pdfStatus;
  }

  /**
   * @return 서버가 리포트 생성을 접수한 UTC 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
