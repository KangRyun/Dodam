package com.ssafy.b209.drawing.domain;

import com.ssafy.b209.child.domain.Child;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/** 아동이 선택한 그림 유형으로 시작하는 단일 그림 활동 세션을 관리한다. */
@Entity
@Table(name = "drawing_sessions")
public class DrawingSession {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "child_id", nullable = false)
  private Child child;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_type_id", nullable = false)
  private DrawingType drawingType;

  @Column(name = "started_by_user_id")
  private Long startedByUserId;

  @Enumerated(EnumType.STRING)
  @Column(name = "input_method", nullable = false)
  private DrawingInputMethod inputMethod;

  @Enumerated(EnumType.STRING)
  @Column(name = "session_status", nullable = false)
  private DrawingSessionStatus sessionStatus;

  @Enumerated(EnumType.STRING)
  @Column(name = "current_stage", nullable = false)
  private DrawingStage currentStage;

  @Column(name = "started_at", nullable = false)
  private LocalDateTime startedAt;

  @Column(name = "completed_at")
  private LocalDateTime completedAt;

  @Column(name = "deleted_at")
  private LocalDateTime deletedAt;

  @Column(name = "idempotency_key", length = 100, unique = true)
  private String idempotencyKey;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected DrawingSession() {}

  private DrawingSession(
      Child child,
      DrawingType drawingType,
      DrawingInputMethod inputMethod,
      LocalDateTime startedAt,
      String idempotencyKey) {
    this.child = child;
    this.drawingType = drawingType;
    this.startedByUserId = null;
    this.inputMethod = inputMethod;
    this.sessionStatus = DrawingSessionStatus.IN_PROGRESS;
    this.currentStage = DrawingStage.DRAWING;
    this.startedAt = startedAt;
    this.completedAt = null;
    this.deletedAt = null;
    this.idempotencyKey = idempotencyKey;
  }

  /**
   * 요청의 필수 값을 검증해 그림 단계에서 시작하는 새 세션을 생성한다.
   *
   * @param child 그림 활동을 수행하는 아동
   * @param drawingType 선택된 그림 활동 유형
   * @param inputMethod 그림 입력 방식
   * @param startedAt 서버가 결정한 UTC 기준 시작 시각
   * @param idempotencyKey 생성 요청을 식별하는 멱등 키
   * @return 초기 상태가 {@link DrawingSessionStatus#IN_PROGRESS}인 새 세션
   */
  public static DrawingSession start(
      Child child,
      DrawingType drawingType,
      DrawingInputMethod inputMethod,
      LocalDateTime startedAt,
      String idempotencyKey) {
    Objects.requireNonNull(child, "child must not be null");
    Objects.requireNonNull(drawingType, "drawingType must not be null");
    Objects.requireNonNull(inputMethod, "inputMethod must not be null");
    Objects.requireNonNull(startedAt, "startedAt must not be null");
    Objects.requireNonNull(idempotencyKey, "idempotencyKey must not be null");
    if (idempotencyKey.isBlank()) {
      throw new IllegalArgumentException("idempotencyKey must not be blank");
    }
    return new DrawingSession(child, drawingType, inputMethod, startedAt, idempotencyKey);
  }

  /**
   * 중복 요청 판단에 사용하는 아동, 그림 유형, 입력 방식이 모두 같은지 확인한다.
   *
   * @param childId 비교할 아동 식별자
   * @param drawingTypeId 비교할 그림 활동 유형 식별자
   * @param inputMethod 비교할 그림 입력 방식
   * @return 핵심 요청 값이 모두 같으면 {@code true}
   */
  public boolean matchesCoreRequest(
      Long childId, Long drawingTypeId, DrawingInputMethod inputMethod) {
    return Objects.equals(child.getId(), childId)
        && Objects.equals(drawingType.getId(), drawingTypeId)
        && this.inputMethod == inputMethod;
  }

  /**
   * 현재 세션이 그림 스냅샷 업로드를 받을 수 있는 상태인지 확인한다.
   *
   * @return 삭제되지 않은 진행 중 DRAWING 단계이면 {@code true}
   */
  public boolean isSnapshotUploadable() {
    return deletedAt == null
        && sessionStatus == DrawingSessionStatus.IN_PROGRESS
        && currentStage == DrawingStage.DRAWING;
  }

  /**
   * 그림 활동 세션 식별자를 반환한다.
   *
   * @return 영속화된 세션 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * 그림 활동을 수행하는 아동을 반환한다.
   *
   * @return 세션에 연결된 아동
   */
  public Child getChild() {
    return child;
  }

  /**
   * 세션에 선택된 그림 활동 유형을 반환한다.
   *
   * @return 선택된 그림 활동 유형
   */
  public DrawingType getDrawingType() {
    return drawingType;
  }

  /**
   * 세션을 시작한 사용자 식별자를 반환한다.
   *
   * @return 인증 연동 전에는 {@code null}
   */
  public Long getStartedByUserId() {
    return startedByUserId;
  }

  /**
   * 그림 입력 방식을 반환한다.
   *
   * @return CANVAS 또는 UPLOAD 입력 방식
   */
  public DrawingInputMethod getInputMethod() {
    return inputMethod;
  }

  /**
   * 세션 처리 상태를 반환한다.
   *
   * @return 현재 세션 처리 상태
   */
  public DrawingSessionStatus getSessionStatus() {
    return sessionStatus;
  }

  /**
   * 그림 활동의 현재 단계를 반환한다.
   *
   * @return 현재 진행 단계
   */
  public DrawingStage getCurrentStage() {
    return currentStage;
  }

  /**
   * 서버가 기록한 공식 시작 시각을 반환한다.
   *
   * @return UTC 기준으로 저장된 시작 시각
   */
  public LocalDateTime getStartedAt() {
    return startedAt;
  }

  /**
   * 세션 완료 시각을 반환한다.
   *
   * @return 완료 전에는 {@code null}
   */
  public LocalDateTime getCompletedAt() {
    return completedAt;
  }

  /**
   * 세션 삭제 시각을 반환한다.
   *
   * @return 삭제되지 않았으면 {@code null}
   */
  public LocalDateTime getDeletedAt() {
    return deletedAt;
  }

  /**
   * 세션 생성 요청의 멱등 키를 반환한다.
   *
   * @return 생성 요청에 사용된 멱등 키
   */
  public String getIdempotencyKey() {
    return idempotencyKey;
  }
}
