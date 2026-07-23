package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * CONV-02 대화 내역 조회에서 질문 메시지에 노출한 선택지 Snapshot을 읽는 읽기 모델이다.
 *
 * <p>선택지 생성 책임을 가진 {@link ConversationMessageOption}과 같은 테이블을 별도 경계로 매핑하며, 조회 응답에 필요한 {@code
 * emoji}와 {@code display_order}까지 함께 읽는다.
 */
@Entity
@Table(name = "conversation_message_options")
public class ConversationHistoryOption {

  @Id private Long id;

  @Column(name = "conversation_message_id", nullable = false)
  private Long conversationMessageId;

  @Column(name = "option_key", nullable = false)
  private String optionKey;

  @Column(name = "option_type", nullable = false)
  private String optionType;

  @Column(name = "option_value", nullable = false)
  private String optionValue;

  @Column(name = "label", nullable = false)
  private String label;

  @Column(name = "emoji")
  private String emoji;

  @Column(name = "display_order", nullable = false)
  private short displayOrder;

  protected ConversationHistoryOption() {}

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

  public short getDisplayOrder() {
    return displayOrder;
  }
}
