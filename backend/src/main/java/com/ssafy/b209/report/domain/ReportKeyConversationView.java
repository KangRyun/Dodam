package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * REPORT-02 보호자용 리포트 상세 조회 전용으로 {@code report_key_conversations} 한 행을 읽는 읽기 모델이다.
 *
 * <p>대표 질문·답변 Snapshot과 원본 메시지 참조만 읽으며, 노출 문구는 저장 시점 Snapshot을 그대로 사용한다.
 */
@Entity
@Table(name = "report_key_conversations")
public class ReportKeyConversationView {

  @Id private Long id;

  @Column(name = "report_id", nullable = false)
  private Long reportId;

  @Column(name = "answer_message_id")
  private Long answerMessageId;

  @Column(name = "answer_text")
  private String answerText;

  @Column(name = "answer_type")
  private String answerType;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  protected ReportKeyConversationView() {}

  /**
   * @return 대표 대화 식별자
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
   * @return 원본 답변 메시지 식별자이며 없으면 {@code null}
   */
  public Long getAnswerMessageId() {
    return answerMessageId;
  }

  /**
   * @return 답변 Snapshot이며 없으면 {@code null}
   */
  public String getAnswerText() {
    return answerText;
  }

  /**
   * @return 답변 유형 Snapshot이며 없으면 {@code null}
   */
  public String getAnswerType() {
    return answerType;
  }

  /**
   * @return 노출 순서
   */
  public short getDisplayOrder() {
    return displayOrder;
  }
}
