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

  @Column(name = "emoji", length = 20)
  private String emoji;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  protected ConversationMessageOption() {}

  private ConversationMessageOption(
      Long conversationMessageId, QuestionOption option, short displayOrder) {
    this.conversationMessageId = conversationMessageId;
    this.optionKey = option.code();
    // 저장 값은 항상 STATIC이다. 질문 응답의 노출 type(OPTION)과 다르며 선택 답변 요청이 이 값을 그대로 보낸다.
    this.optionType = "STATIC";
    this.optionValue = option.code();
    this.label = option.label();
    this.emoji = option.emoji();
    this.displayOrder = displayOrder;
  }

  public static ConversationMessageOption snapshot(
      Long conversationMessageId, QuestionOption option, short displayOrder) {
    return new ConversationMessageOption(conversationMessageId, option, displayOrder);
  }

  public Long getId() {
    return id;
  }

  public Long getConversationMessageId() {
    return conversationMessageId;
  }

  public String getOptionKey() {
    return optionKey;
  }

  public String getOptionType() {
    return optionType;
  }

  public String getOptionValue() {
    return optionValue;
  }

  public String getLabel() {
    return label;
  }

  public String getEmoji() {
    return emoji;
  }
}
