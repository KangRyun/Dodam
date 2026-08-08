package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/** DB v1.2 conversation_messages의 OPTION_ANSWER 행만 생성·조회하는 전용 Entity다. */
@Entity
@Table(name = "conversation_messages")
public class OptionAnswerMessage {

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

  @Column(name = "needs_guardian_confirmation", nullable = false)
  private boolean needsGuardianConfirmation;

  /**
   * 음성 답변 행의 STT 처리 상태이며 이 Entity는 읽기만 한다.
   *
   * <p>OPTION_ANSWER 행은 이 값을 쓰지 않으므로 {@code insertable=false}·{@code updatable=false}로 두어 저장 경로를
   * 그대로 유지한다. 중복 답변 판정에서 실패한 음성 답변을 제외하려고 매핑만 추가했다({@code
   * OptionAnswerMessageRepository.existsAnswerForQuestion}).
   */
  @Column(name = "speech_status", insertable = false, updatable = false)
  private String speechStatus;

  @Column(name = "is_skipped", nullable = false)
  private boolean skipped;

  /**
   * 뒤에 온 명시적 답에 자리를 내준 시각이며 살아 있으면 {@code null}이다.
   *
   * <p>아이가 보기를 고르면, 아직 글로 옮겨지지 않은 자동 음성 답이 여기로 물러난다. <strong>지우지 않는다</strong> — 아동 기록에서 무엇이 언제 왜
   * 물러났는지는 되짚을 수 있어야 한다.
   */
  @Column(name = "superseded_at")
  private LocalDateTime supersededAt;

  /** 자리를 대신한 답 메시지 식별자다. */
  @Column(name = "superseded_by_message_id")
  private Long supersededByMessageId;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  protected OptionAnswerMessage() {}

  /**
   * 이 답이 뒤에 온 명시적 답에 자리를 내주게 한다.
   *
   * @param supersededByMessageId 자리를 대신한 답 메시지 식별자
   * @param supersededAt 물러난 시각
   */
  public void supersede(Long supersededByMessageId, LocalDateTime supersededAt) {
    this.supersededByMessageId =
        Objects.requireNonNull(supersededByMessageId, "supersededByMessageId must not be null");
    this.supersededAt = Objects.requireNonNull(supersededAt, "supersededAt must not be null");
  }

  /**
   * @return 아직 글로 옮겨지지 않은 음성 답이면 {@code true}
   */
  public boolean isVoiceAnswerAwaitingTranscript() {
    return "VOICE_ANSWER".equals(messageType)
        && ("PENDING".equals(speechStatus) || "PROCESSING".equals(speechStatus));
  }

  /**
   * @return 물러난 시각이며 살아 있으면 {@code null}
   */
  public LocalDateTime getSupersededAt() {
    return supersededAt;
  }

  /**
   * 질문에 연결되는 아동 선택형 답변 메시지를 생성한다.
   *
   * <p>{@code parentMessageId}에는 같은 세션의 QUESTION 메시지로 검증된 값만 전달받아 복합 FK가 답변과 질문의 부모-자식 관계를 보장한다.
   *
   * @param conversationSessionId 답변이 속한 대화 세션 ID
   * @param questionMessageId 실제 QUESTION 타입인 부모 메시지 ID
   * @param sequence 세션 잠금에서 계산한 유일 순번
   * @param directText 문장 직접 입력 값 또는 {@code null}
   * @param createdAt 서버 생성 시각
   * @return 영속화 전 선택형 답변 메시지
   */
  public static OptionAnswerMessage of(
      Long conversationSessionId,
      Long questionMessageId,
      int sequence,
      String directText,
      LocalDateTime createdAt) {
    OptionAnswerMessage message = new OptionAnswerMessage();
    message.conversationSessionId = conversationSessionId;
    message.parentMessageId = questionMessageId;
    message.messageSequence = sequence;
    message.senderType = "CHILD";
    message.messageType = "OPTION_ANSWER";
    message.rawText = directText;
    message.needsGuardianConfirmation = false;
    message.skipped = false;
    message.createdAt = createdAt;
    return message;
  }

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

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
