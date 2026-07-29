package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * 질문 메시지의 건너뜀 표시만 읽고 갱신하는 CONV-08 전용 Entity다.
 *
 * <p>질문 생성 책임을 가진 {@link ConversationMessage}의 매핑을 바꾸지 않기 위해 같은 {@code conversation_messages} 테이블을 별도
 * 경계로 매핑한다({@link QuestionTtsMessage}와 동일한 방식).
 */
@Entity
@Table(name = "conversation_messages")
public class SkippableQuestionMessage {

  private static final String QUESTION_MESSAGE_TYPE = "QUESTION";

  @Id private Long id;

  @Column(name = "conversation_session_id", nullable = false)
  private Long conversationSessionId;

  @Column(name = "message_type", nullable = false)
  private String messageType;

  @Column(name = "is_skipped", nullable = false)
  private boolean skipped;

  /** JPA가 질문 메시지를 복원할 때 사용한다. */
  protected SkippableQuestionMessage() {}

  /**
   * 메시지 식별자를 반환한다.
   *
   * @return 대화 메시지 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * 소속 대화 세션 식별자를 반환한다.
   *
   * @return 대화 세션 식별자
   */
  public Long getConversationSessionId() {
    return conversationSessionId;
  }

  /**
   * 이 메시지가 AI 질문인지 판단한다.
   *
   * <p>답변 메시지는 건너뛸 대상이 아니다. 호출자는 이 값이 거짓이면 질문을 찾지 못한 것으로 처리한다.
   *
   * @return 메시지 유형이 {@code QUESTION}이면 {@code true}
   */
  public boolean isQuestion() {
    return QUESTION_MESSAGE_TYPE.equals(messageType);
  }

  /**
   * 건너뜀 여부를 반환한다.
   *
   * @return 이미 건너뛴 질문이면 {@code true}
   */
  public boolean isSkipped() {
    return skipped;
  }

  /**
   * 질문을 건너뛴 상태로 표시한다.
   *
   * <p>이미 건너뛴 질문에 다시 호출해도 상태와 결과가 같다. 재전송이 오류가 되지 않도록 멱등하게 둔다.
   */
  public void skip() {
    this.skipped = true;
  }
}
