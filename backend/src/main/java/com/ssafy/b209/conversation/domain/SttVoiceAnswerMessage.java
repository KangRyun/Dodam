package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * 288이 생성한 음성 답변 행의 STT 상태와 결과만 갱신하는 289 전용 읽기·갱신 Entity다.
 *
 * <p>기존 {@link VoiceAnswerMessage}의 업로드 생성 책임을 변경하지 않기 위해 같은 테이블을 별도 경계로 매핑한다.
 */
@Entity
@Table(name = "conversation_messages")
public class SttVoiceAnswerMessage {
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

  @Column(name = "audio_storage_key")
  private String audioStorageKey;

  @Column(name = "speech_status")
  private String speechStatus;

  @Column(name = "stt_text")
  private String sttText;

  @Column(name = "stt_confidence", precision = 5, scale = 4)
  private BigDecimal sttConfidence;

  @Column(name = "needs_guardian_confirmation", nullable = false)
  private boolean needsGuardianConfirmation;

  @Column(name = "created_at", nullable = false, updatable = false)
  private LocalDateTime createdAt;

  protected SttVoiceAnswerMessage() {}

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

  public String getAudioStorageKey() {
    return audioStorageKey;
  }

  public String getSpeechStatus() {
    return speechStatus;
  }

  public String getSttText() {
    return sttText;
  }

  public BigDecimal getSttConfidence() {
    return sttConfidence;
  }

  public boolean isNeedsGuardianConfirmation() {
    return needsGuardianConfirmation;
  }

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
