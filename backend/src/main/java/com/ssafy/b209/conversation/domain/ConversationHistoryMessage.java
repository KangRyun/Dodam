package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * CONV-02 대화 내역 조회 전용으로 {@code conversation_messages} 한 행을 읽는 읽기 모델이다.
 *
 * <p>메시지 생성 책임을 가진 {@link ConversationMessage}·{@link VoiceAnswerMessage}·{@link
 * OptionAnswerMessage}와 같은 테이블을 별도 경계로 매핑해 조회에 필요한 모든 컬럼을 함께 읽는다. 이 Entity는 상태를 변경하지 않는다.
 */
@Entity
@Table(name = "conversation_messages")
public class ConversationHistoryMessage {

  @Id private Long id;

  @Column(name = "conversation_session_id", nullable = false)
  private Long conversationSessionId;

  @Column(name = "parent_message_id")
  private Long parentMessageId;

  @Column(name = "message_sequence", nullable = false)
  private int messageSequence;

  @Column(name = "sender_type", nullable = false)
  private String senderType;

  @Column(name = "message_type", nullable = false)
  private String messageType;

  @Column(name = "raw_text")
  private String rawText;

  @Column(name = "stt_text")
  private String sttText;

  @Column(name = "speech_status")
  private String speechStatus;

  @Column(name = "stt_confidence", precision = 5, scale = 4)
  private BigDecimal sttConfidence;

  @Column(name = "needs_guardian_confirmation", nullable = false)
  private boolean needsGuardianConfirmation;

  @Column(name = "is_skipped", nullable = false)
  private boolean skipped;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  protected ConversationHistoryMessage() {}

  public Long getId() {
    return id;
  }

  public Long getConversationSessionId() {
    return conversationSessionId;
  }

  public Long getParentMessageId() {
    return parentMessageId;
  }

  public int getMessageSequence() {
    return messageSequence;
  }

  public String getSenderType() {
    return senderType;
  }

  public String getMessageType() {
    return messageType;
  }

  public String getRawText() {
    return rawText;
  }

  public String getSttText() {
    return sttText;
  }

  public String getSpeechStatus() {
    return speechStatus;
  }

  public BigDecimal getSttConfidence() {
    return sttConfidence;
  }

  public boolean isNeedsGuardianConfirmation() {
    return needsGuardianConfirmation;
  }

  public boolean isSkipped() {
    return skipped;
  }

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  /**
   * 저장된 DB 메시지 유형이 QUESTION인지 판별한다.
   *
   * @return 선택지·대상 객체 Snapshot을 함께 조립해야 하는 질문 메시지이면 {@code true}
   */
  public boolean isQuestion() {
    return "QUESTION".equals(messageType);
  }

  /**
   * 저장된 DB 메시지 유형이 선택형 답변인지 판별한다.
   *
   * @return 선택 응답을 함께 조립해야 하는 답변 메시지이면 {@code true}
   */
  public boolean isOptionAnswer() {
    return "OPTION_ANSWER".equals(messageType);
  }
}
