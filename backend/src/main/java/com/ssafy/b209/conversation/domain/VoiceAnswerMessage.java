package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.LocalDateTime;

/** DB v1.2의 PENDING 음성 답변 행만 생성·조회하는 전용 Entity다. */
@Entity
@Table(name = "conversation_messages")
public class VoiceAnswerMessage {
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

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

  @Column(name = "audio_storage_key")
  private String audioStorageKey;

  /** DB v1.2의 SHA-256 고정 길이(64자) 문자열 컬럼과 매핑한다. */
  @Column(name = "audio_checksum_sha256", columnDefinition = "CHAR(64)")
  private String audioChecksumSha256;

  @Column(name = "speech_status")
  private String speechStatus;

  /** DB v1.2의 DECIMAL(5,4) 신뢰도 컬럼과 정밀도를 보존해 매핑한다. */
  @Column(name = "stt_confidence", precision = 5, scale = 4)
  private BigDecimal sttConfidence;

  @Column(name = "needs_guardian_confirmation", nullable = false)
  private boolean needsGuardianConfirmation;

  @Column(name = "is_skipped", nullable = false)
  private boolean skipped;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  protected VoiceAnswerMessage() {}

  /**
   * STT 연계 전 PENDING 상태의 음성 답변을 생성한다.
   *
   * @param conversationSessionId 답변이 속한 대화 세션 ID
   * @param questionMessageId 실제 QUESTION 타입인 부모 메시지 ID
   * @param sequence 세션 잠금에서 계산한 유일 순번
   * @param audioStorageKey 음성 Root 기준 상대 저장 key
   * @param checksumSha256 저장 파일 SHA-256
   * @param createdAt 서버 생성 시각
   * @return 영속화 전 음성 답변 메시지
   */
  public static VoiceAnswerMessage pending(
      Long conversationSessionId,
      Long questionMessageId,
      int sequence,
      String audioStorageKey,
      String checksumSha256,
      LocalDateTime createdAt) {
    VoiceAnswerMessage message = new VoiceAnswerMessage();
    message.conversationSessionId = conversationSessionId;
    message.parentMessageId = questionMessageId;
    message.messageSequence = sequence;
    message.senderType = "CHILD";
    message.messageType = "VOICE_ANSWER";
    message.rawText = null;
    message.sttText = null;
    message.audioStorageKey = audioStorageKey;
    message.audioChecksumSha256 = checksumSha256;
    message.speechStatus = "PENDING";
    message.sttConfidence = null;
    message.needsGuardianConfirmation = false;
    message.skipped = false;
    message.createdAt = createdAt;
    return message;
  }

  public Long getId() {
    return id;
  }

  public Long getParentMessageId() {
    return parentMessageId;
  }

  public Long getConversationSessionId() {
    return conversationSessionId;
  }

  public int getMessageSequence() {
    return messageSequence;
  }

  public String getMessageType() {
    return messageType;
  }

  public String getSenderType() {
    return senderType;
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

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
