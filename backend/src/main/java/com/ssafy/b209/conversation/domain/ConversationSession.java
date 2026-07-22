package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** V1의 대화 세션이며 질문 수 상한은 잠금 상태에서만 변경한다. */
@Entity
@Table(name = "conversation_sessions")
public class ConversationSession {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "drawing_session_id", nullable = false)
  private Long drawingSessionId;

  @Column(name = "difficulty_snapshot", nullable = false)
  private String difficultySnapshot;

  @Column(name = "max_question_count", nullable = false, columnDefinition = "SMALLINT")
  private int maxQuestionCount;

  @Column(name = "question_count", nullable = false, columnDefinition = "SMALLINT")
  private int questionCount;

  protected ConversationSession() {}

  public Long getId() {
    return id;
  }

  public Long getDrawingSessionId() {
    return drawingSessionId;
  }

  public ConversationDifficulty getDifficulty() {
    return ConversationDifficulty.valueOf(difficultySnapshot);
  }

  public int getMaxQuestionCount() {
    return maxQuestionCount;
  }

  public int getQuestionCount() {
    return questionCount;
  }

  public boolean canAskQuestion() {
    return questionCount < maxQuestionCount;
  }

  public void increaseQuestionCount() {
    if (!canAskQuestion()) {
      throw new IllegalStateException("Question count limit has been reached");
    }
    questionCount++;
  }
}
