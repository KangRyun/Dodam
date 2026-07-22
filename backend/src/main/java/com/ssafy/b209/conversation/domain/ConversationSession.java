package com.ssafy.b209.conversation.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/** V1의 대화 세션이며 질문 수 상한은 잠금 상태에서만 변경한다. */
@Entity
@Table(name = "conversation_sessions")
public class ConversationSession {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "drawing_session_id", nullable = false)
  private Long drawingSessionId;

  @Column(name = "conversation_status", nullable = false)
  private String conversationStatus;

  @Column(name = "difficulty_snapshot", nullable = false)
  private String difficultySnapshot;

  @Column(name = "max_question_count", nullable = false, columnDefinition = "SMALLINT")
  private int maxQuestionCount;

  @Column(name = "question_count", nullable = false, columnDefinition = "SMALLINT")
  private int questionCount;

  @Column(name = "started_at", nullable = false)
  private LocalDateTime startedAt;

  protected ConversationSession() {}

  /**
   * 그림 활동에 연결되는 진행 중 대화 세션을 생성한다.
   *
   * @param drawingSessionId 연결할 그림 활동 세션 식별자
   * @param difficultySnapshot 시작 시점 아동 질문 난이도 Snapshot
   * @param maxQuestionCount 서버 정책상 허용할 최대 질문 수
   * @param startedAt 서버가 결정한 UTC 시작 시각
   * @return 영속화 전 대화 세션
   * @throws IllegalArgumentException 식별자·난이도·질문 수가 유효하지 않은 경우
   */
  public static ConversationSession start(
      Long drawingSessionId,
      String difficultySnapshot,
      int maxQuestionCount,
      LocalDateTime startedAt) {
    if (drawingSessionId == null || drawingSessionId <= 0) {
      throw new IllegalArgumentException("drawingSessionId must be positive");
    }
    if (difficultySnapshot == null || difficultySnapshot.isBlank() || maxQuestionCount <= 0) {
      throw new IllegalArgumentException("Invalid conversation session start values");
    }
    ConversationSession session = new ConversationSession();
    session.drawingSessionId = drawingSessionId;
    session.conversationStatus = "CONVERSING";
    session.difficultySnapshot = difficultySnapshot;
    session.maxQuestionCount = maxQuestionCount;
    session.questionCount = 0;
    session.startedAt = Objects.requireNonNull(startedAt, "startedAt must not be null");
    return session;
  }

  public Long getId() {
    return id;
  }

  public Long getDrawingSessionId() {
    return drawingSessionId;
  }

  public ConversationDifficulty getDifficulty() {
    return ConversationDifficulty.valueOf(difficultySnapshot);
  }

  /**
   * 시작 시점에 저장한 DB v1.2 난이도 Snapshot 문자열을 반환한다.
   *
   * @return 아동 프로필 변경과 무관한 질문 난이도 Snapshot
   */
  public String getDifficultySnapshot() {
    return difficultySnapshot;
  }

  public int getMaxQuestionCount() {
    return maxQuestionCount;
  }

  public int getQuestionCount() {
    return questionCount;
  }

  /**
   * 대화의 현재 상태를 반환한다.
   *
   * @return DB v1.2 대화 상태 문자열
   */
  public String getConversationStatus() {
    return conversationStatus;
  }

  /**
   * 대화 시작 시각을 반환한다.
   *
   * @return 서버가 기록한 UTC 시작 시각
   */
  public LocalDateTime getStartedAt() {
    return startedAt;
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
