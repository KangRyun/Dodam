package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code analysis_conversation_summaries} 한 행을 읽는 읽기 모델이다.
 *
 * <p>보호자용 대화 요약의 대체 출처로 요약 문구만 읽는다. AI 추정 감정·확률 등 전문가 전용 컬럼은 읽지 않는다.
 */
@Entity
@Table(name = "analysis_conversation_summaries")
public class ReportConversationSummaryView {

  @Id
  @Column(name = "conversation_summary_id")
  private Long id;

  @Column(name = "analysis_id", nullable = false)
  private Long analysisId;

  @Column(name = "summary_text")
  private String summaryText;

  protected ReportConversationSummaryView() {}

  /**
   * @return 대화 요약 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 요약이 속한 최종 분석 식별자
   */
  public Long getAnalysisId() {
    return analysisId;
  }

  /**
   * @return 관찰 보조 표현으로 작성한 대화 요약이며 없으면 {@code null}
   */
  public String getSummaryText() {
    return summaryText;
  }
}
