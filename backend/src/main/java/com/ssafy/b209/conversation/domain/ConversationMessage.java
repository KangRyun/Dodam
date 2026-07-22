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

  @Column(name = "parent_message_id")
  private Long parentMessageId;

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
      Long conversationSessionId,
      Long parentMessageId,
      Long questionTemplateId,
      int messageSequence,
      String rawText) {
    this.conversationSessionId = conversationSessionId;
    this.parentMessageId = parentMessageId;
    this.questionTemplateId = questionTemplateId;
    this.messageSequence = messageSequence;
    this.senderType = "AI";
    this.messageType = "QUESTION";
    this.rawText = rawText;
  }

  /**
   * 이전 답변에 연결된 AI 질문 메시지를 생성한다.
   *
   * <p>{@code parentMessageId}는 같은 대화 세션의 답변 메시지로 검증된 값만 전달받으며, 첫 질문이면 {@code null}이다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @param parentMessageId 이전 답변 메시지 식별자 또는 첫 질문의 {@code null}
   * @param questionTemplateId 사용한 폴백 템플릿 식별자 또는 {@code null}
   * @param messageSequence 세션 안에서 유일한 메시지 순번
   * @param questionText 아동에게 노출할 질문
   * @return 영속화 전 AI 질문 메시지
   */
  public static ConversationMessage aiQuestion(
      Long conversationSessionId,
      Long parentMessageId,
      Long questionTemplateId,
      int messageSequence,
      String questionText) {
    return new ConversationMessage(
        conversationSessionId, parentMessageId, questionTemplateId, messageSequence, questionText);
  }

  /**
   * 부모 메시지가 없는 첫 질문을 생성한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @param questionTemplateId 사용한 폴백 템플릿 식별자 또는 {@code null}
   * @param messageSequence 세션 안에서 유일한 메시지 순번
   * @param questionText 아동에게 노출할 질문
   * @return 영속화 전 AI 질문 메시지
   */
  public static ConversationMessage aiQuestion(
      Long conversationSessionId,
      Long questionTemplateId,
      int messageSequence,
      String questionText) {
    return aiQuestion(
        conversationSessionId, null, questionTemplateId, messageSequence, questionText);
  }

  public Long getId() {
    return id;
  }

  public int getMessageSequence() {
    return messageSequence;
  }

  /**
   * 이 질문이 이어받은 이전 답변 메시지를 반환한다.
   *
   * @return 첫 질문이면 {@code null}, 후속 질문이면 검증된 답변 메시지 식별자
   */
  public Long getParentMessageId() {
    return parentMessageId;
  }

  /**
   * 메시지가 속한 대화 세션을 반환한다.
   *
   * @return 대화 세션 식별자
   */
  public Long getConversationSessionId() {
    return conversationSessionId;
  }

  /**
   * 이 메시지가 답변 유형인지 판별한다.
   *
   * @return 음성·선택·텍스트 답변이면 {@code true}
   */
  public boolean isAnswerMessage() {
    return "VOICE_ANSWER".equals(messageType)
        || "OPTION_ANSWER".equals(messageType)
        || "TEXT_ANSWER".equals(messageType);
  }

  public String getRawText() {
    return rawText;
  }
}
