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
   * 현재 세션이 Canvas 행동 이벤트 배치를 받을 수 있는지 확인한다.
   *
   * @return Canvas 입력 방식이며 삭제되지 않은 진행 중 DRAWING 단계이면 {@code true}
   */
  public boolean canAcceptStrokeBatch() {
    return inputMethod == DrawingInputMethod.CANVAS && isSnapshotUploadable();
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
   * 최종 그림 저장이 끝난 세션을 대화 준비용 분석 단계로 전환한다.
   *
   * <p>진행 중인 {@link DrawingStage#DRAWING} 세션에서만 호출할 수 있다. 이 전이는 전체 그림 활동을 완료하지 않으며, 분석 결과가 확정될 때까지
   * 추가 스냅샷 업로드를 차단한다.
   *
   * @throws IllegalStateException 삭제되었거나 진행 중이 아니거나 DRAWING 단계가 아닌 경우
   */
  public void startDrawingAnalysis() {
    if (!isAnalysisRequestable()) {
      throw new IllegalStateException("그림 작성 단계의 진행 중인 세션만 분석을 시작할 수 있습니다.");
    }
    currentStage = DrawingStage.ANALYZING;
  }

  /**
   * 대화 준비용 그림 분석을 확정하고 후속 대화·감정 선택 단계로 전환한다.
   *
   * <p>분석 성공과 실패 모두 이 전이를 사용한다. 분석 실패 시에도 저장된 최종 그림을 유지하고 폴백 질문을 제공할 수 있도록 세션 자체는 진행 상태를 유지한다.
   *
   * @throws IllegalStateException 삭제되었거나 진행 중이 아니거나 ANALYZING 단계가 아닌 경우
   */
  public void finishDrawingAnalysis() {
    finishDrawingAnalysis(false);
  }

  /**
   * 대화 종료 여부를 반영해 최종 그림 분석 이후의 후속 단계를 확정한다.
   *
   * <p>그림 작성 중 이미 대화를 마친 그림일기는 다시 대화를 열지 않고 감정 회고로 이동한다.
   *
   * @param conversationCompleted 연결된 대화가 그림 완료 전에 이미 종료되었는지 여부
   * @throws IllegalStateException 삭제되었거나 진행 중이 아니거나 ANALYZING 단계가 아닌 경우
   */
  public void finishDrawingAnalysis(boolean conversationCompleted) {
    if (deletedAt != null
        || sessionStatus != DrawingSessionStatus.IN_PROGRESS
        || currentStage != DrawingStage.ANALYZING) {
      throw new IllegalStateException("분석 중인 진행 세션만 대화 단계로 전환할 수 있습니다.");
    }
    currentStage = conversationCompleted ? DrawingStage.REFLECTION : DrawingStage.CONVERSING;
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
   * 대화를 마친 그림 활동을 감정 회고 단계로 전환한다.
   *
   * <p>이미 감정 회고 단계이면 상태를 유지하며, 감정·제목 값은 변경하지 않는다.
   *
   * @throws IllegalStateException 삭제됐거나 진행 중이 아니거나 대화 단계가 아닌 경우
   */
  public void enterReflection() {
    if (deletedAt != null || sessionStatus != DrawingSessionStatus.IN_PROGRESS) {
      throw new IllegalStateException("진행 중인 그림 활동만 감정 회고로 이동할 수 있습니다.");
    }
    if (currentStage == DrawingStage.REFLECTION) {
      return;
    }
    if (currentStage != DrawingStage.CONVERSING) {
      throw new IllegalStateException("대화 단계에서만 감정 회고로 이동할 수 있습니다.");
    }
    currentStage = DrawingStage.REFLECTION;
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
   * HTP 묶음 안의 한 그림 세션을 개별 리포트 생성 없이 완료한다.
   *
   * <p>HTP는 HOUSE, TREE, PERSON 세 결과를 모두 모은 뒤 하나의 리포트를 생성하므로 일반 활동의 REPORTING 단계를 거치지 않는다. 대화 종료 후
   * REFLECTION 단계에 도달한 HTP 세션에서만 HTP Application Service가 호출해야 한다.
   *
   * @param completedAt 서버가 결정한 UTC 기준 단계 완료 시각
   * @throws NullPointerException {@code completedAt}이 {@code null}인 경우
   * @throws IllegalStateException 삭제됐거나 진행 중이 아니거나 REFLECTION 단계가 아닌 경우
   */
  public void completeHtpStep(LocalDateTime completedAt) {
    Objects.requireNonNull(completedAt, "completedAt must not be null");
    if (deletedAt != null
        || sessionStatus != DrawingSessionStatus.IN_PROGRESS
        || currentStage != DrawingStage.REFLECTION) {
      throw new IllegalStateException("감정 회고 단계의 진행 중인 HTP 세션만 완료할 수 있습니다.");
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
   * 리포트 생성에 실패한 Session을 같은 REPORTING 단계에서 재시작한다.
   *
   * <p>재생성은 새 Analysis와 Report 버전으로 진행되므로 완료 시각과 이전 생성 결과를 변경하지 않는다.
   *
   * @throws IllegalStateException 삭제됐거나 FAILED/REPORTING 상태가 아닌 경우
   */
  public void restartReporting() {
    if (deletedAt != null
        || sessionStatus != DrawingSessionStatus.FAILED
        || currentStage != DrawingStage.REPORTING) {
      throw new IllegalStateException(
          "only a failed reporting session can restart report generation");
    }
    sessionStatus = DrawingSessionStatus.IN_PROGRESS;
  }

  /**
   * 진행 중인 활동의 재개를 종료하고 포기 상태로 전환한다.
   *
   * <p>사용자의 명시적 삭제와 달리 {@code deletedAt}을 기록하지 않아 그림·획·대화 자료를 보존한다. 현재 단계는 중단 지점을 감사할 수 있도록 유지한다.
   *
   * @param abandonedAt 서버가 결정한 포기 시각
   * @throws NullPointerException {@code abandonedAt}이 {@code null}인 경우
   * @throws IllegalStateException 진행 중인 세션이 아닌 경우
   */
  public void abandon(LocalDateTime abandonedAt) {
    Objects.requireNonNull(abandonedAt, "abandonedAt must not be null");
    if (deletedAt != null || sessionStatus != DrawingSessionStatus.IN_PROGRESS) {
      throw new IllegalStateException("진행 중인 그림 활동만 포기할 수 있습니다.");
    }
    sessionStatus = DrawingSessionStatus.ABANDONED;
    completedAt = abandonedAt;
  }

  /**
   * 그림 활동을 삭제 상태로 전환하고 삭제 시각을 기록한다.
   *
   * <p>현재 단계와 완료 시각은 감사 및 운영 기록을 위해 유지한다.
   *
   * @param deletedAt 서버가 결정한 UTC 기준 삭제 시각
   * @throws NullPointerException {@code deletedAt}이 {@code null}인 경우
   * @throws IllegalStateException 이미 삭제된 세션인 경우
   */
  public void softDelete(LocalDateTime deletedAt) {
    Objects.requireNonNull(deletedAt, "deletedAt must not be null");
    if (this.deletedAt != null || sessionStatus == DrawingSessionStatus.DELETED) {
      throw new IllegalStateException("이미 삭제된 그림 활동입니다.");
    }
    sessionStatus = DrawingSessionStatus.DELETED;
    this.deletedAt = deletedAt;
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
