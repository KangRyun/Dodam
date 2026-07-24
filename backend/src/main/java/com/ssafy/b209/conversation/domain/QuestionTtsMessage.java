package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * AI 질문 행의 TTS 음성 상태와 저장 위치만 선점·갱신하는 CONV-04 전용 읽기·갱신 Entity다.
 *
 * <p>질문 생성 책임을 가진 {@link ConversationMessage}의 매핑을 바꾸지 않기 위해 같은 {@code conversation_messages} 테이블을
 * 별도 경계로 매핑한다. 내부 저장 key는 API 응답이나 로그에 노출하지 않는다.
 */
@Entity
@Table(name = "conversation_messages")
public class QuestionTtsMessage {

  @Id private Long id;

  @Column(name = "conversation_session_id", nullable = false)
  private Long conversationSessionId;

  @Column(name = "sender_type", nullable = false)
  private String senderType;

  @Column(name = "message_type", nullable = false)
  private String messageType;

  @Column(name = "raw_text")
  private String rawText;

  @Column(name = "audio_storage_key")
  private String audioStorageKey;

  @Column(name = "audio_url")
  private String audioUrl;

  @Column(name = "speech_status")
  private String speechStatus;

  protected QuestionTtsMessage() {}

  public Long getId() {
    return id;
  }

  public Long getConversationSessionId() {
    return conversationSessionId;
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

  public String getAudioStorageKey() {
    return audioStorageKey;
  }

  public String getAudioUrl() {
    return audioUrl;
  }

  public String getSpeechStatus() {
    return speechStatus;
  }

  /**
   * 이 행이 음성을 생성할 수 있는 AI 질문인지 판별한다.
   *
   * @return {@code AI} 발신 {@code QUESTION} 메시지이면 {@code true}
   */
  public boolean isAiQuestion() {
    return "AI".equals(senderType) && "QUESTION".equals(messageType);
  }
}
