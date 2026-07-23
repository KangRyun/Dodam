package com.ssafy.b209.conversation.domain;

import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/** 282번 대화 시작에 필요한 그림 활동 세션의 최소 읽기·상태 전이 모델이다. */
@Entity
@Table(name = "drawing_sessions")
public class ConversationStartDrawingSession {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "child_id", nullable = false)
  private Long childId;

  @Enumerated(EnumType.STRING)
  @Column(name = "session_status", nullable = false)
  private DrawingSessionStatus sessionStatus;

  @Enumerated(EnumType.STRING)
  @Column(name = "current_stage", nullable = false)
  private DrawingStage currentStage;

  @Column(name = "deleted_at")
  private LocalDateTime deletedAt;

  protected ConversationStartDrawingSession() {}

  /**
   * 대화 시작 가능 상태인지 확인한다.
   *
   * @return 진행 중이며 ANALYZING 또는 CONVERSING 단계이면 {@code true}
   */
  public boolean canStartConversation() {
    return deletedAt == null
        && sessionStatus == DrawingSessionStatus.IN_PROGRESS
        && (currentStage == DrawingStage.ANALYZING || currentStage == DrawingStage.CONVERSING);
  }

  /** 대화 세션 생성이 완료되면 그림 활동 화면 단계를 대화로 전이한다. */
  public void moveToConversing() {
    currentStage = DrawingStage.CONVERSING;
  }

  /**
   * @return 그림 활동 세션 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소유 아동 식별자
   */
  public Long getChildId() {
    return childId;
  }
}
