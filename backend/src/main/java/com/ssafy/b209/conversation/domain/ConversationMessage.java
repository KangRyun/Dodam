package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** v1.2 conversation_messages의 실제 제시 질문 저장 모델이다. */
@Entity
@Table(name = "conversation_messages")
public class ConversationMessage {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "conversation_session_id", nullable = false)
  private Long conversationSessionId;

  @Column(name = "question_template_id")
  private Long questionTemplateId;

  @Column(name = "message_sequence", nullable = false)
  private int messageSequence;

  @Column(name = "sender_type", nullable = false)
  private String senderType;

  @Column(name = "message_type", nullable = false)
  private String messageType;

  @Column(name = "raw_text")
  private String rawText;

  protected ConversationMessage() {}

  private ConversationMessage(
      Long conversationSessionId, Long questionTemplateId, int messageSequence, String rawText) {
    this.conversationSessionId = conversationSessionId;
    this.questionTemplateId = questionTemplateId;
    this.messageSequence = messageSequence;
    this.senderType = "AI";
    this.messageType = "QUESTION";
    this.rawText = rawText;
  }

  public static ConversationMessage aiQuestion(
      Long conversationSessionId,
      Long questionTemplateId,
      int messageSequence,
      String questionText) {
    return new ConversationMessage(
        conversationSessionId, questionTemplateId, messageSequence, questionText);
  }

  public Long getId() {
    return id;
  }

  public int getMessageSequence() {
    return messageSequence;
  }

  public String getRawText() {
    return rawText;
  }
}
