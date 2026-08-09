package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code report_activity_summaries} 한 행을 읽는 읽기 모델이다.
 *
 * <p>그림 활동과 대화의 객관적 집계 수치, 보호자용 대화 요약만 읽는다.
 */
@Entity
@Table(name = "report_activity_summaries")
public class ReportActivitySummaryView {

  @Id
  @Column(name = "report_id")
  private Long reportId;

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

  @Column(name = "conversation_summary")
  private String conversationSummary;

  protected ReportActivitySummaryView() {}

  /**
   * @return 리포트 식별자
   */
  public Long getReportId() {
    return reportId;
  }

  /**
   * @return 그림 활동 시간(ms)이며 미집계면 {@code null}
   */
  public Long getDrawingDurationMs() {
    return drawingDurationMs;
  }

  /**
   * @return 일시 정지 횟수이며 미집계면 {@code null}
   */
  public Integer getPauseCount() {
    return pauseCount;
  }

  /**
   * @return 지우기 횟수이며 미집계면 {@code null}
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
   * @return 대화 질문 수이며 미집계면 {@code null}
   */
  public Integer getConversationQuestionCount() {
    return conversationQuestionCount;
  }

  /**
   * @return 대화 응답 수이며 미집계면 {@code null}
   */
  public Integer getConversationAnsweredCount() {
    return conversationAnsweredCount;
  }

  /**
   * @return 건너뛴 질문 수이며 미집계면 {@code null}
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
}
