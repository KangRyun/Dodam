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

  @Column(name = "title", length = 200)
  private String title;

  @Column(name = "expressed_emotion_text", columnDefinition = "TEXT")
  private String expressedEmotionText;

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
    this.title = null;
    this.expressedEmotionText = null;
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
   * 현재 세션이 최종 그림 분석 요청을 시작할 수 있는 상태인지 확인한다.
   *
   * <p>분석 요청은 최종 스냅샷 업로드와 같은 그림 단계에서만 허용하며, 삭제되거나 완료된 세션의 재분석은 별도 정책으로 분리한다.
   *
   * @return 삭제되지 않은 진행 중 DRAWING 단계이면 {@code true}
   */
  public boolean isAnalysisRequestable() {
    return isSnapshotUploadable();
  }

  /**
   * 현재 세션이 감정 표현을 최초 저장하거나 수정할 수 있는지 확인한다.
   *
   * @return 삭제되지 않은 진행 중 CONVERSING 또는 REFLECTION 단계이면 {@code true}
   */
  public boolean canSaveReflection() {
    return deletedAt == null
        && sessionStatus == DrawingSessionStatus.IN_PROGRESS
        && (currentStage == DrawingStage.CONVERSING || currentStage == DrawingStage.REFLECTION);
  }

  /**
   * 그림 활동의 제목과 직접 표현을 저장하고 감정 돌아보기 단계로 전이한다.
   *
   * @param title 정규화된 그림 제목
   * @param expressedEmotionText 정규화된 아동의 직접 감정 표현
   */
  public void saveReflection(String title, String expressedEmotionText) {
    if (!canSaveReflection()) {
      throw new IllegalStateException("현재 단계에서는 감정 회고를 저장할 수 없습니다.");
    }
    this.title = title;
    this.expressedEmotionText = expressedEmotionText;
    this.currentStage = DrawingStage.REFLECTION;
  }

  /**
   * 그림 활동 완료 접수를 받을 수 있는 상태인지 확인한다.
   *
   * @return 삭제되지 않은 진행 중 REFLECTION 단계이면 {@code true}
   */
  public boolean canRequestCompletion() {
    return deletedAt == null
        && sessionStatus == DrawingSessionStatus.IN_PROGRESS
        && currentStage == DrawingStage.REFLECTION;
  }

  /**
   * 최종 분석과 선택적 리포트 생성 대기 단계로 전환한다.
   *
   * <p>이 전이는 비동기 작업 접수만 나타내므로 세션을 완료 처리하거나 완료 시각을 기록하지 않는다.
   *
   * @throws IllegalStateException 현재 세션이 완료 접수를 받을 수 없는 경우
   */
  public void startReporting() {
    if (!canRequestCompletion()) {
      throw new IllegalStateException("현재 단계에서는 완료 처리를 접수할 수 없습니다.");
    }
    currentStage = DrawingStage.REPORTING;
  }

  /**
   * 최종 분석과 리포트 저장이 성공한 활동을 완료 상태로 전이한다.
   *
   * <p>리포트 결과 저장 Transaction 안에서 호출해 분석·리포트·세션 상태가 함께 반영되도록 한다.
   *
   * @param completedAt 서버가 결정한 UTC 기준 완료 시각
   * @throws NullPointerException {@code completedAt}이 {@code null}인 경우
   * @throws IllegalStateException 삭제됐거나 REPORTING 중인 진행 세션이 아닌 경우
   */
  public void completeReporting(LocalDateTime completedAt) {
    Objects.requireNonNull(completedAt, "completedAt must not be null");
    if (deletedAt != null
        || sessionStatus != DrawingSessionStatus.IN_PROGRESS
        || currentStage != DrawingStage.REPORTING) {
      throw new IllegalStateException("리포트 생성 중인 세션만 완료할 수 있습니다.");
    }
    sessionStatus = DrawingSessionStatus.COMPLETED;
    currentStage = DrawingStage.COMPLETED;
    this.completedAt = completedAt;
  }

  /**
   * 최종 분석 또는 리포트 생성에 실패한 활동을 실패 상태로 전이한다.
   *
   * <p>완료 시각은 기록하지 않고 REPORTING 단계를 유지해 실패 지점을 나타낸다. 세션 상태가 {@link DrawingSessionStatus#FAILED}로
   * 바뀌므로 새 활동의 진행 중 중복 검사에서는 제외된다.
   *
   * @throws IllegalStateException REPORTING 중인 진행 세션이 아닌 경우
   */
  public void failReporting() {
    if (sessionStatus != DrawingSessionStatus.IN_PROGRESS
        || currentStage != DrawingStage.REPORTING) {
      throw new IllegalStateException("리포트 생성 중인 세션만 실패 처리할 수 있습니다.");
    }
    sessionStatus = DrawingSessionStatus.FAILED;
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
   * 그림 활동 제목을 반환한다.
   *
   * @return 제목을 작성하지 않았으면 {@code null}
   */
  public String getTitle() {
    return title;
  }

  /**
   * 아동이 직접 표현한 감정 내용을 반환한다.
   *
   * @return 직접 표현을 작성하지 않았으면 {@code null}
   */
  public String getExpressedEmotionText() {
    return expressedEmotionText;
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
