package com.ssafy.b209.conversation.domain;

import com.ssafy.b209.conversation.dto.DetectedObject;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;

/** v1.2 질문 메시지의 대상 객체와 Bounding Box Snapshot이다. */
@Entity
@Table(name = "conversation_message_targets")
public class ConversationMessageTarget {

  @Id
  @Column(name = "conversation_message_id")
  private Long conversationMessageId;

  @Column(name = "object_code", length = 50)
  private String objectCode;

  @Column(name = "object_name", length = 100)
  private String objectName;

  @Column(name = "bbox_x", nullable = false, precision = 8, scale = 6)
  private BigDecimal bboxX;

  @Column(name = "bbox_y", nullable = false, precision = 8, scale = 6)
  private BigDecimal bboxY;

  @Column(name = "bbox_width", nullable = false, precision = 8, scale = 6)
  private BigDecimal bboxWidth;

  @Column(name = "bbox_height", nullable = false, precision = 8, scale = 6)
  private BigDecimal bboxHeight;

  protected ConversationMessageTarget() {}

  private ConversationMessageTarget(Long conversationMessageId, DetectedObject targetObject) {
    this.conversationMessageId = conversationMessageId;
    this.objectCode = targetObject.objectCode();
    this.objectName = targetObject.objectName();
    this.bboxX = BigDecimal.valueOf(targetObject.boundingBox().x());
    this.bboxY = BigDecimal.valueOf(targetObject.boundingBox().y());
    this.bboxWidth = BigDecimal.valueOf(targetObject.boundingBox().width());
    this.bboxHeight = BigDecimal.valueOf(targetObject.boundingBox().height());
  }

  public static ConversationMessageTarget snapshot(
      Long conversationMessageId, DetectedObject targetObject) {
    return new ConversationMessageTarget(conversationMessageId, targetObject);
  }
}
