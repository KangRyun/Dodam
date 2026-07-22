package com.ssafy.b209.conversation.domain;

import com.ssafy.b209.conversation.dto.QuestionOption;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** v1.2 질문 메시지에 실제 노출한 선택지 Snapshot이다. */
@Entity
@Table(name = "conversation_message_options")
public class ConversationMessageOption {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "conversation_message_id", nullable = false)
  private Long conversationMessageId;

  @Column(name = "option_key", nullable = false, length = 80)
  private String optionKey;

  @Column(name = "option_type", nullable = false, length = 30)
  private String optionType;

  @Column(name = "option_value", nullable = false, length = 255)
  private String optionValue;

  @Column(name = "label", nullable = false, length = 200)
  private String label;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  protected ConversationMessageOption() {}

  private ConversationMessageOption(
      Long conversationMessageId, QuestionOption option, short displayOrder) {
    this.conversationMessageId = conversationMessageId;
    this.optionKey = option.code();
    this.optionType = "STATIC";
    this.optionValue = option.code();
    this.label = option.label();
    this.displayOrder = displayOrder;
  }

  public static ConversationMessageOption snapshot(
      Long conversationMessageId, QuestionOption option, short displayOrder) {
    return new ConversationMessageOption(conversationMessageId, option, displayOrder);
  }
}
