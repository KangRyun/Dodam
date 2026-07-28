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

  @Column(name = "failure_reason", length = 100)
  private String failureReason;

  @Column(name = "failed_at")
  private LocalDateTime failedAt;

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
   * 생성 중 리포트를 완료 상태로 전환하고 전문가 검토 권장 여부와 한계 문구를 갱신한다.
   *
   * @param expertReviewRecommended 전문가 검토 권장 여부
   * @param limitationsText 리포트 해석 시 적용할 필수 한계 문구
   * @param updatedAt 완료 처리를 기록한 UTC 시각
   * @throws IllegalStateException 현재 상태가 GENERATING이 아닌 경우
   * @throws IllegalArgumentException 한계 문구가 비어 있는 경우
   */
  public void complete(
      boolean expertReviewRecommended, String limitationsText, LocalDateTime updatedAt) {
    ensureGenerating();
    this.status = ReportStatus.COMPLETED;
    this.expertReviewRecommended = expertReviewRecommended;
    this.limitationsText = requireText(limitationsText, "limitationsText");
    this.updatedAt = Objects.requireNonNull(updatedAt, "updatedAt must not be null");
  }

  /**
   * 생성 중 리포트를 실패 상태로 전환하고 실패 분류 코드와 실패 시각을 보존한다.
   *
   * <p>{@code limitationsText}는 보호자에게 노출하는 한계 문구이고, {@code failureReason}은 원문이나 개인정보를 담지 않는 내부 진단용
   * 분류 코드다. 두 값은 서로 독립적으로 저장한다.
   *
   * @param limitationsText 실패 상황을 알리는 필수 한계 문구
   * @param failureReason 원문을 포함하지 않는 실패 분류 코드이며 없으면 {@code null}
   * @param failedAt 실패를 기록한 UTC 시각이며 상태 갱신 시각으로도 사용한다
   * @throws IllegalStateException 현재 상태가 GENERATING이 아닌 경우
   * @throws IllegalArgumentException 한계 문구가 비어 있는 경우
   */
  public void fail(String limitationsText, String failureReason, LocalDateTime failedAt) {
    ensureGenerating();
    this.status = ReportStatus.FAILED;
    this.expertReviewRecommended = false;
    this.limitationsText = requireText(limitationsText, "limitationsText");
    this.failureReason = failureReason;
    this.failedAt = Objects.requireNonNull(failedAt, "failedAt must not be null");
    this.updatedAt = failedAt;
  }

  /**
   * 실패한 HTP 종합 리포트를 재시도할 때 이전 버전을 목록에서 숨긴다.
   *
   * <p>실패 이력과 분석 근거는 삭제하지 않고 보존하며, 보호자에게는 새로 접수한 단일 리포트만 노출한다.
   *
   * @param hiddenAt 숨김 처리한 UTC 시각
   * @throws IllegalStateException 실패 상태가 아닌 리포트인 경우
   */
  public void hideFailedVersion(LocalDateTime hiddenAt) {
    Objects.requireNonNull(hiddenAt, "hiddenAt must not be null");
    if (status != ReportStatus.FAILED) {
      throw new IllegalStateException("only failed report can be hidden for retry");
    }
    status = ReportStatus.HIDDEN;
    updatedAt = hiddenAt;
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
   * @return 실패 상태일 때의 내부 진단용 실패 분류 코드이며 실패하지 않았으면 {@code null}
   */
  public String getFailureReason() {
    return failureReason;
  }

  /**
   * @return 리포트 생성이 실패한 UTC 시각이며 실패하지 않았으면 {@code null}
   */
  public LocalDateTime getFailedAt() {
    return failedAt;
  }

  /**
   * @return 서버가 리포트 생성을 접수한 UTC 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  /**
   * @return 리포트 상태가 마지막으로 갱신된 UTC 시각
   */
  public LocalDateTime getUpdatedAt() {
    return updatedAt;
  }

  private void ensureGenerating() {
    if (status != ReportStatus.GENERATING) {
      throw new IllegalStateException("only generating report can change its completion state");
    }
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
