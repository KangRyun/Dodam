package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.MapsId;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import java.util.Objects;

/**
 * 리포트의 객관적 활동 요약을 리포트와 1:1로 저장한다.
 *
 * <p>대화 관련 수치는 실제 대화 메시지 집계값이며, 행동 수치는 해석 없이 객관적 기록으로만 담는다.
 */
@Entity
@Table(name = "report_activity_summaries")
public class ReportActivitySummary {

  @Id
  @Column(name = "report_id")
  private Long reportId;

  @MapsId
  @OneToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "report_id")
  private Report report;

  @Column(name = "drawing_duration_ms")
  private Long drawingDurationMs;

  @Column(name = "pause_count")
  private Integer pauseCount;

  @Column(name = "erase_count")
  private Integer eraseCount;

  @Column(name = "pressure_available", nullable = false)
  private boolean pressureAvailable;

  @Column(name = "conversation_question_count")
  private Integer conversationQuestionCount;

  @Column(name = "conversation_answered_count")
  private Integer conversationAnsweredCount;

  @Column(name = "conversation_skipped_count")
  private Integer conversationSkippedCount;

  @Column(name = "conversation_summary", columnDefinition = "TEXT")
  private String conversationSummary;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportActivitySummary() {}

  private ReportActivitySummary(
      Report report,
      Long drawingDurationMs,
      Integer pauseCount,
      Integer eraseCount,
      boolean pressureAvailable,
      int conversationQuestionCount,
      int conversationAnsweredCount,
      int conversationSkippedCount,
      String conversationSummary) {
    this.report = Objects.requireNonNull(report, "report must not be null");
    this.drawingDurationMs = requireNonNegative(drawingDurationMs, "drawingDurationMs");
    this.pauseCount = requireNonNegative(pauseCount, "pauseCount");
    this.eraseCount = requireNonNegative(eraseCount, "eraseCount");
    this.pressureAvailable = pressureAvailable;
    this.conversationQuestionCount =
        requireNonNegative(conversationQuestionCount, "conversationQuestionCount");
    this.conversationAnsweredCount =
        requireNonNegative(conversationAnsweredCount, "conversationAnsweredCount");
    this.conversationSkippedCount =
        requireNonNegative(conversationSkippedCount, "conversationSkippedCount");
    this.conversationSummary = conversationSummary;
  }

  /**
   * 리포트에 연결되는 활동 요약을 생성한다.
   *
   * @param report 요약이 속한 리포트
   * @param drawingDurationMs 그림 활동 시간이며 측정하지 못했으면 {@code null}
   * @param pauseCount 일시 정지 횟수이며 측정하지 못했으면 {@code null}
   * @param eraseCount 지우기 횟수이며 측정하지 못했으면 {@code null}
   * @param pressureAvailable 필압 데이터 존재 여부
   * @param conversationQuestionCount 실제 제시한 질문 수
   * @param conversationAnsweredCount 실제 응답한 답변 수
   * @param conversationSkippedCount 건너뛴 질문 수
   * @param conversationSummary 보호자용 대화 요약이며 없으면 {@code null}
   * @return 저장 가능한 활동 요약
   * @throws IllegalArgumentException 수치가 음수인 경우
   */
  public static ReportActivitySummary create(
      Report report,
      Long drawingDurationMs,
      Integer pauseCount,
      Integer eraseCount,
      boolean pressureAvailable,
      int conversationQuestionCount,
      int conversationAnsweredCount,
      int conversationSkippedCount,
      String conversationSummary) {
    return new ReportActivitySummary(
        report,
        drawingDurationMs,
        pauseCount,
        eraseCount,
        pressureAvailable,
        conversationQuestionCount,
        conversationAnsweredCount,
        conversationSkippedCount,
        conversationSummary);
  }

  /**
   * @return 요약이 속한 리포트 식별자
   */
  public Long getReportId() {
    return reportId;
  }

  /**
   * @return 그림 활동 시간이며 측정하지 못했으면 {@code null}
   */
  public Long getDrawingDurationMs() {
    return drawingDurationMs;
  }

  /**
   * @return 일시 정지 횟수이며 측정하지 못했으면 {@code null}
   */
  public Integer getPauseCount() {
    return pauseCount;
  }

  /**
   * @return 지우기 횟수이며 측정하지 못했으면 {@code null}
   */
  public Integer getEraseCount() {
    return eraseCount;
  }

  /**
   * @return 필압 데이터 존재 여부
   */
  public boolean isPressureAvailable() {
    return pressureAvailable;
  }

  /**
   * @return 실제 제시한 질문 수
   */
  public Integer getConversationQuestionCount() {
    return conversationQuestionCount;
  }

  /**
   * @return 실제 응답한 답변 수
   */
  public Integer getConversationAnsweredCount() {
    return conversationAnsweredCount;
  }

  /**
   * @return 건너뛴 질문 수
   */
  public Integer getConversationSkippedCount() {
    return conversationSkippedCount;
  }

  /**
   * @return 보호자용 대화 요약이며 없으면 {@code null}
   */
  public String getConversationSummary() {
    return conversationSummary;
  }

  private static Long requireNonNegative(Long value, String name) {
    if (value != null && value < 0) {
      throw new IllegalArgumentException(name + " must not be negative");
    }
    return value;
  }

  private static Integer requireNonNegative(Integer value, String name) {
    if (value != null && value < 0) {
      throw new IllegalArgumentException(name + " must not be negative");
    }
    return value;
  }
}
