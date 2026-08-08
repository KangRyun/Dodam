package com.ssafy.b209.conversation.domain;

import com.ssafy.b209.child.domain.QuestionDifficulty;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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

  @Enumerated(EnumType.STRING)
  @Column(name = "completion_reason", length = 30)
  private ConversationCompletionReason completionReason;

  @Column(name = "started_at", nullable = false)
  private LocalDateTime startedAt;

  @Column(name = "completed_at")
  private LocalDateTime completedAt;

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

  /**
   * 시작 시점에 고정한 질문 난이도를 반환한다.
   *
   * @return DB v1.2와 API 계약에 정의된 질문 난이도
   */
  public QuestionDifficulty getDifficulty() {
    return QuestionDifficulty.valueOf(difficultySnapshot);
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

  /**
   * 현재 세션이 질문을 계속 생성할 수 있는 진행 상태인지 판별한다.
   *
   * @return 상태가 {@code CONVERSING}이면 {@code true}
   */
  public boolean isConversing() {
    return "CONVERSING".equals(conversationStatus);
  }

  /**
   * 대화가 명시적으로 완료됐는지 판별한다.
   *
   * @return 상태가 {@code COMPLETED}이면 {@code true}
   */
  public boolean isCompleted() {
    return "COMPLETED".equals(conversationStatus);
  }

  /**
   * 진행 중인 대화를 완료하고 최초 종료 사유와 완료 시각을 기록한다.
   *
   * <p>이미 완료된 세션에 대한 재호출은 최초 기록을 유지해 멱등하게 처리한다.
   *
   * @param reason 대화를 끝낸 직접적인 계기
   * @param completedAt 서버가 결정한 UTC 완료 시각
   * @throws NullPointerException 종료 사유나 완료 시각이 {@code null}인 경우
   * @throws IllegalStateException 진행 중 또는 완료 상태가 아닌 경우
   */
  public void complete(ConversationCompletionReason reason, LocalDateTime completedAt) {
    Objects.requireNonNull(reason, "reason must not be null");
    Objects.requireNonNull(completedAt, "completedAt must not be null");
    if (isCompleted()) {
      return;
    }
    if (!isConversing()) {
      throw new IllegalStateException("진행 중인 대화만 완료할 수 있습니다.");
    }
    conversationStatus = "COMPLETED";
    completionReason = reason;
    this.completedAt = completedAt;
  }

  /**
   * 끝난 대화를 다시 열 수 있는 상태인지 판별한다 — 상태를 바꾸지 않는 읽기 전용 판정이다.
   *
   * <p>그림일기는 대화가 끝난 뒤에도 아이가 캔버스에 계속 그린다. 그림 한 장에 대화 세션은 평생 하나뿐이므로({@code
   * conversation_sessions.drawing_session_id} UNIQUE) 새 세션을 여는 대신 끝난 세션을 다시 연다.
   *
   * <p><b>상한 도달로 끝난 대화만</b> 다시 연다. {@code CHILD_REQUEST}(아이가 그만하겠다고 했다)·{@code
   * GUARDIAN_REQUEST}·{@code NO_MORE_QUESTION}은 명시적인 종료 의사라, 그림이 바뀌었다는 이유로 되살리지 않는다. 이미 절대 상한까지 올라간
   * 대화도 다시 열지 않는다 — 그때는 진짜로 끝이다.
   *
   * @param absoluteMax 설정으로도 넘을 수 없는 질문 수 절대 상한
   * @return 재개할 수 있으면 {@code true}
   */
  public boolean isReopenEligible(int absoluteMax) {
    return isCompleted()
        && completionReason == ConversationCompletionReason.QUESTION_LIMIT_REACHED
        && maxQuestionCount < absoluteMax;
  }

  /**
   * 재개했을 때 적용될 질문 수 상한을 계산한다 — 상태는 바꾸지 않는다.
   *
   * <p>{@link #reopen}과 같은 계산을 쓰므로, 재개 전에 "재개하면 몇 문이 되는가"를 알아야 하는 쪽(AI 페이싱 문맥)은 이 값을 쓴다.
   *
   * @param increment 재개 시 더할 질문 수
   * @param absoluteMax 넘을 수 없는 절대 상한
   * @return 절대 상한으로 자른 재개 후 질문 수 상한
   */
  public int reopenedMaxQuestionCount(int increment, int absoluteMax) {
    return Math.min(maxQuestionCount + increment, absoluteMax);
  }

  /**
   * 끝난 대화를 다시 열고 질문 수 상한을 그만큼 늘린다.
   *
   * <p>동시 요청 경쟁을 피하려면 세션 비관 잠금 안에서만 호출해야 한다. 호출 측이 미리 {@link #isReopenEligible}로 걸렀더라도 잠금 안에서 조건을
   * 다시 검증한다.
   *
   * @param increment 늘릴 질문 수
   * @param absoluteMax 넘을 수 없는 절대 상한
   * @throws IllegalArgumentException 늘릴 질문 수가 1 미만인 경우
   * @throws IllegalStateException 재개할 수 있는 상태가 아닌 경우
   */
  public void reopen(int increment, int absoluteMax) {
    if (increment < 1) {
      throw new IllegalArgumentException("increment must be at least 1 but was " + increment);
    }
    if (!isReopenEligible(absoluteMax)) {
      throw new IllegalStateException("상한 도달로 끝난 대화만 다시 열 수 있습니다.");
    }
    maxQuestionCount = reopenedMaxQuestionCount(increment, absoluteMax);
    conversationStatus = "CONVERSING";
    // 종료 사유·시각은 지운다. 두 값은 "지금 완료 상태다"를 설명하는 값이라 CONVERSING 과 함께
    //   남으면 행 자체가 모순된다 — getCompletionReason 의 계약(완료 전에는 null)도 여기서 깨진다.
    //   다시 끝날 때 complete()가 그때의 사유·시각을 기록하고, "한 번 끝났다 다시 열렸다"는 사실은
    //   종료 행동 이벤트(S15P11B209-973)와 늘어난 max_question_count 에 남는다.
    completionReason = null;
    completedAt = null;
  }

  /**
   * 최초 완료 시 기록된 종료 사유를 반환한다.
   *
   * @return 완료 전에는 {@code null}, 완료 후에는 종료 사유
   */
  public ConversationCompletionReason getCompletionReason() {
    return completionReason;
  }

  /**
   * 대화 완료 시각을 반환한다.
   *
   * @return 완료 전에는 {@code null}, 완료 후에는 UTC 완료 시각
   */
  public LocalDateTime getCompletedAt() {
    return completedAt;
  }

  public void increaseQuestionCount() {
    if (!canAskQuestion()) {
      throw new IllegalStateException("Question count limit has been reached");
    }
    questionCount++;
  }
}
