package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;

/**
 * CONV-02 대화 내역 조회에서 질문 메시지의 대상 객체와 Bounding Box Snapshot을 읽는 읽기 모델이다.
 *
 * <p>대상 객체 생성 책임을 가진 {@link ConversationMessageTarget}과 같은 테이블을 별도 경계로 매핑해 조회에 필요한 값을 읽는다.
 */
@Entity
@Table(name = "conversation_message_targets")
public class ConversationHistoryTarget {

  @Id
  @Column(name = "conversation_message_id")
  private Long conversationMessageId;

  @Column(name = "object_code")
  private String objectCode;

  @Column(name = "object_name")
  private String objectName;

  @Column(name = "bbox_x", nullable = false, precision = 8, scale = 6)
  private BigDecimal bboxX;

  @Column(name = "bbox_y", nullable = false, precision = 8, scale = 6)
  private BigDecimal bboxY;

  @Column(name = "bbox_width", nullable = false, precision = 8, scale = 6)
  private BigDecimal bboxWidth;

  @Column(name = "bbox_height", nullable = false, precision = 8, scale = 6)
  private BigDecimal bboxHeight;

  protected ConversationHistoryTarget() {}

  public Long getConversationMessageId() {
    return conversationMessageId;
  }

  public String getObjectCode() {
    return objectCode;
  }

  public String getObjectName() {
    return objectName;
  }

  public BigDecimal getBboxX() {
    return bboxX;
  }

  public BigDecimal getBboxY() {
    return bboxY;
  }

  public BigDecimal getBboxWidth() {
    return bboxWidth;
  }

  public BigDecimal getBboxHeight() {
    return bboxHeight;
  }
}
