package com.ssafy.b209.drawing.htp.domain;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingType;
import jakarta.persistence.CascadeType;
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
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * HOUSE, TREE, PERSON 세 그림 세션을 하나의 HTP 활동으로 묶어 순서를 관리한다.
 *
 * <p>각 그림의 저장·분석·대화는 기존 {@link DrawingSession}이 담당하고, 이 Entity는 단계 주제와 다음 단계 생성 가능 여부만 책임진다. 종합
 * 분석·리포트는 세 단계가 모두 끝난 뒤 별도 Application Service에서 처리해야 한다.
 */
@Entity
@Table(name = "htp_assessments")
public class HtpAssessment {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "child_id", nullable = false)
  private Child child;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_type_id", nullable = false)
  private DrawingType drawingType;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 20)
  private HtpAssessmentStatus status;

  @Column(name = "current_step_order", nullable = false, columnDefinition = "TINYINT")
  private int currentStepOrder;

  @Column(name = "expires_at", nullable = false)
  private LocalDateTime expiresAt;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "completed_at")
  private LocalDateTime completedAt;

  @Column(name = "idempotency_key", nullable = false, unique = true, length = 100)
  private String idempotencyKey;

  @OneToMany(mappedBy = "assessment", cascade = CascadeType.ALL, orphanRemoval = true)
  @OrderBy("stepOrder ASC")
  private List<HtpAssessmentStep> steps = new ArrayList<>();

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected HtpAssessment() {}

  private HtpAssessment(
      Child child,
      DrawingType drawingType,
      LocalDateTime createdAt,
      LocalDateTime expiresAt,
      String idempotencyKey) {
    this.child = child;
    this.drawingType = drawingType;
    this.status = HtpAssessmentStatus.IN_PROGRESS;
    this.currentStepOrder = 1;
    this.createdAt = createdAt;
    this.expiresAt = expiresAt;
    this.completedAt = null;
    this.idempotencyKey = idempotencyKey;
  }

  /**
   * HOUSE 그림 세션을 첫 단계로 가진 HTP 활동을 시작한다.
   *
   * @param child HTP 활동을 수행하는 아동
   * @param drawingType 코드가 {@code HTP}인 그림 활동 유형
   * @param houseSession 첫 HOUSE 그림 세션
   * @param createdAt 서버가 결정한 UTC 기준 생성 시각
   * @param expiresAt 생성 시각보다 뒤인 재개 만료 시각
   * @param idempotencyKey 시작 요청을 식별하는 멱등 키
   * @return 첫 단계가 연결된 진행 중 HTP 활동
   */
  public static HtpAssessment start(
      Child child,
      DrawingType drawingType,
      DrawingSession houseSession,
      LocalDateTime createdAt,
      LocalDateTime expiresAt,
      String idempotencyKey) {
    Objects.requireNonNull(child, "child must not be null");
    Objects.requireNonNull(drawingType, "drawingType must not be null");
    Objects.requireNonNull(houseSession, "houseSession must not be null");
    Objects.requireNonNull(createdAt, "createdAt must not be null");
    Objects.requireNonNull(expiresAt, "expiresAt must not be null");
    Objects.requireNonNull(idempotencyKey, "idempotencyKey must not be null");
    if (!"HTP".equals(drawingType.getCode())) {
      throw new IllegalArgumentException("drawingType must be HTP");
    }
    if (!expiresAt.isAfter(createdAt)) {
      throw new IllegalArgumentException("expiresAt must be after createdAt");
    }
    if (idempotencyKey.isBlank()) {
      throw new IllegalArgumentException("idempotencyKey must not be blank");
    }

    HtpAssessment assessment =
        new HtpAssessment(child, drawingType, createdAt, expiresAt, idempotencyKey);
    assessment.steps.add(
        new HtpAssessmentStep(
            assessment, 1, HtpDrawingSubject.HOUSE, houseSession, idempotencyKey, createdAt));
    return assessment;
  }

  /**
   * 완료된 현재 단계 다음에 계약상 다음 주제의 그림 세션을 연결한다.
   *
   * @param nextSession 다음 주제에 사용할 새 그림 세션
   * @param advancedAt 서버가 결정한 UTC 기준 전이 시각
   * @throws IllegalStateException 활동이 진행 중이 아니거나 만료됐거나 현재 단계가 미완료이거나 마지막 단계인 경우
   */
  public void advance(DrawingSession nextSession, LocalDateTime advancedAt) {
    Objects.requireNonNull(nextSession, "nextSession must not be null");
    Objects.requireNonNull(advancedAt, "advancedAt must not be null");
    if (status != HtpAssessmentStatus.IN_PROGRESS) {
      throw new IllegalStateException("진행 중인 HTP 활동만 다음 단계로 이동할 수 있습니다.");
    }
    if (advancedAt.isAfter(expiresAt)) {
      status = HtpAssessmentStatus.EXPIRED;
      throw new IllegalStateException("만료된 HTP 활동은 다음 단계로 이동할 수 없습니다.");
    }
    HtpAssessmentStep currentStep = getCurrentStep();
    if (currentStep.getDrawingSession().getSessionStatus() != DrawingSessionStatus.COMPLETED) {
      throw new IllegalStateException("현재 그림 단계가 완료되지 않았습니다.");
    }
    HtpDrawingSubject nextSubject =
        currentStep
            .getDrawingSubject()
            .next()
            .orElseThrow(() -> new IllegalStateException("마지막 HTP 그림 단계입니다."));
    int nextOrder = currentStepOrder + 1;
    steps.add(
        new HtpAssessmentStep(
            this,
            nextOrder,
            nextSubject,
            nextSession,
            nextSession.getIdempotencyKey(),
            advancedAt));
    currentStepOrder = nextOrder;
  }

  /**
   * 진행 중인 HTP 활동을 포기 상태로 전환한다.
   *
   * @param abandonedAt 서버가 결정한 UTC 기준 포기 시각
   */
  public void abandon(LocalDateTime abandonedAt) {
    Objects.requireNonNull(abandonedAt, "abandonedAt must not be null");
    if (status == HtpAssessmentStatus.ABANDONED) {
      return;
    }
    if (status != HtpAssessmentStatus.IN_PROGRESS) {
      throw new IllegalStateException("진행 중인 HTP 활동만 포기할 수 있습니다.");
    }
    status = HtpAssessmentStatus.ABANDONED;
    completedAt = abandonedAt;
  }

  /**
   * 재개 가능 시간이 지난 HTP 활동을 만료 상태로 전환한다.
   *
   * @param expiredAt 서버가 결정한 UTC 기준 만료 처리 시각
   */
  public void expire(LocalDateTime expiredAt) {
    Objects.requireNonNull(expiredAt, "expiredAt must not be null");
    if (status == HtpAssessmentStatus.EXPIRED) {
      return;
    }
    if (status != HtpAssessmentStatus.IN_PROGRESS || expiredAt.isBefore(expiresAt)) {
      throw new IllegalStateException("재개 기한이 지난 진행 중 HTP 활동만 만료할 수 있습니다.");
    }
    status = HtpAssessmentStatus.EXPIRED;
    completedAt = expiredAt;
  }

  /**
   * 현재 진행 순서에 연결된 단계를 반환한다.
   *
   * @return 현재 HOUSE, TREE 또는 PERSON 단계
   */
  public HtpAssessmentStep getCurrentStep() {
    return steps.stream()
        .filter(step -> step.getStepOrder() == currentStepOrder)
        .findFirst()
        .orElseThrow(() -> new IllegalStateException("현재 HTP 단계가 존재하지 않습니다."));
  }

  /**
   * HTP 활동 식별자를 반환한다.
   *
   * @return 영속화 전이면 {@code null}
   */
  public Long getId() {
    return id;
  }

  /**
   * HTP 활동을 수행하는 아동을 반환한다.
   *
   * @return 연결된 아동
   */
  public Child getChild() {
    return child;
  }

  /**
   * HTP 활동 유형을 반환한다.
   *
   * @return 코드가 {@code HTP}인 그림 유형
   */
  public DrawingType getDrawingType() {
    return drawingType;
  }

  /**
   * HTP 묶음 처리 상태를 반환한다.
   *
   * @return 현재 처리 상태
   */
  public HtpAssessmentStatus getStatus() {
    return status;
  }

  /**
   * 현재 그림 단계 순서를 반환한다.
   *
   * @return 1~3
   */
  public int getCurrentStepOrder() {
    return currentStepOrder;
  }

  /**
   * HTP 활동을 재개할 수 있는 만료 시각을 반환한다.
   *
   * @return UTC 기준 생성 시각에서 24시간 뒤
   */
  public LocalDateTime getExpiresAt() {
    return expiresAt;
  }

  /**
   * 시작 요청의 멱등 키를 반환한다.
   *
   * @return HTP 생성 요청의 {@code Idempotency-Key}
   */
  public String getIdempotencyKey() {
    return idempotencyKey;
  }

  /**
   * 생성된 HTP 그림 단계를 고정 순서로 반환한다.
   *
   * @return 외부에서 변경할 수 없는 단계 목록
   */
  public List<HtpAssessmentStep> getSteps() {
    return Collections.unmodifiableList(steps);
  }
}
