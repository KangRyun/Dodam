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
   * @param hasUsableIntermediateAnalysis 같은 그림일기 세션에서 성공한 중간 객체 탐지 여부
   * @return 진행 중이고 현재 단계에 필요한 분석 근거가 충족되면 {@code true}
   */
  public boolean canStartConversation(boolean hasUsableIntermediateAnalysis) {
    return deletedAt == null
        && sessionStatus == DrawingSessionStatus.IN_PROGRESS
        && ((currentStage == DrawingStage.DRAWING && hasUsableIntermediateAnalysis)
            || currentStage == DrawingStage.ANALYZING
            || currentStage == DrawingStage.CONVERSING);
  }

  /**
   * 대화 세션 생성이 완료되면 최종 그림 분석 단계만 대화 단계로 전이한다.
   *
   * <p>그림일기의 중간 분석으로 대화를 시작한 경우에는 획·Draft 저장을 계속 받아야 하므로 DRAWING 단계를 유지한다.
   */
  public void moveToConversing() {
    if (currentStage != DrawingStage.DRAWING) {
      currentStage = DrawingStage.CONVERSING;
    }
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
