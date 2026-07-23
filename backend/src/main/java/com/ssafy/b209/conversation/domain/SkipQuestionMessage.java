package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * DB v1.2 conversation_messages의 QUESTION 행 건너뛰기 표시만 담당하는 전용 Entity다.
 *
 * <p>새 행을 만들지 않고 이미 존재하는 질문 메시지를 잠금 트랜잭션 안에서 조회해 {@code is_skipped}만 전이한다. 형제 선택형 답변 API의 전용 write
 * Entity 관례를 따라 질문 생성 write 모델과 책임을 분리한다.
 */
@Entity
@Table(name = "conversation_messages")
public class SkipQuestionMessage {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "conversation_session_id", nullable = false)
  private Long conversationSessionId;

  @Column(name = "parent_message_id")
  private Long parentMessageId;

  @Column(name = "message_type", nullable = false)
  private String messageType;

  @Column(name = "is_skipped", nullable = false)
  private boolean skipped;

  protected SkipQuestionMessage() {}

  /** 질문을 건너뛴 것으로 표시한다. 이미 건너뛴 질문에 다시 호출해도 상태가 그대로 유지되어 멱등하다. */
  public void markSkipped() {
    this.skipped = true;
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

  public String getMessageType() {
    return messageType;
  }

  public boolean isSkipped() {
    return skipped;
  }
}
