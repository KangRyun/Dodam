package com.ssafy.b209.drawing.htp.domain;

import com.ssafy.b209.drawing.domain.DrawingSession;
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

/**
 * HTP 묶음의 한 그림 주제와 실제 {@link DrawingSession}을 연결한다.
 *
 * <p>주제는 클라이언트가 업로드마다 다시 전달하지 않으며, 이 연결을 기준으로 AI 요청의 {@code drawingSubject}를 결정한다.
 */
@Entity
@Table(name = "htp_assessment_steps")
public class HtpAssessmentStep {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "htp_assessment_id", nullable = false)
  private HtpAssessment assessment;

  @Column(name = "step_order", nullable = false, columnDefinition = "TINYINT")
  private int stepOrder;

  @Enumerated(EnumType.STRING)
  @Column(name = "drawing_subject", nullable = false, length = 20)
  private HtpDrawingSubject drawingSubject;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_session_id", nullable = false)
  private DrawingSession drawingSession;

  @Column(name = "subject_detected")
  private Boolean subjectDetected;

  @Column(name = "retry_count", nullable = false, columnDefinition = "TINYINT")
  private int retryCount;

  @Column(name = "transition_idempotency_key", nullable = false, length = 100)
  private String transitionIdempotencyKey;

  @Column(name = "completion_idempotency_key", length = 100)
  private String completionIdempotencyKey;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected HtpAssessmentStep() {}

  HtpAssessmentStep(
      HtpAssessment assessment,
      int stepOrder,
      HtpDrawingSubject drawingSubject,
      DrawingSession drawingSession,
      String transitionIdempotencyKey,
      LocalDateTime createdAt) {
    this.assessment = Objects.requireNonNull(assessment, "assessment must not be null");
    this.stepOrder = stepOrder;
    this.drawingSubject = Objects.requireNonNull(drawingSubject, "drawingSubject must not be null");
    this.drawingSession = Objects.requireNonNull(drawingSession, "drawingSession must not be null");
    this.transitionIdempotencyKey =
        Objects.requireNonNull(
            transitionIdempotencyKey, "transitionIdempotencyKey must not be null");
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
    this.subjectDetected = null;
    this.retryCount = 0;
    this.completionIdempotencyKey = null;
  }

  /**
   * 단계의 고정 순서를 반환한다.
   *
   * @return HOUSE부터 시작하는 1~3 순서
   */
  public int getStepOrder() {
    return stepOrder;
  }

  /**
   * @return 이 단계를 소유한 HTP 활동 묶음
   */
  public HtpAssessment getAssessment() {
    return assessment;
  }

  /**
   * 서버가 이 단계에 지정한 HTP 그림 주제를 반환한다.
   *
   * @return HOUSE, TREE 또는 PERSON
   */
  public HtpDrawingSubject getDrawingSubject() {
    return drawingSubject;
  }

  /**
   * 이 단계의 그리기·분석·대화를 담당하는 세션을 반환한다.
   *
   * @return 단계 생성 후 바뀌지 않는 그림 세션
   */
  public DrawingSession getDrawingSession() {
    return drawingSession;
  }

  /**
   * 주제 전체 객체 탐지 여부를 반환한다.
   *
   * @return 아직 판정 전이면 {@code null}, 판정 후 탐지 여부
   */
  public Boolean getSubjectDetected() {
    return subjectDetected;
  }

  /**
   * 이 단계에서 추가 그리기를 요청한 횟수를 반환한다.
   *
   * @return 0 또는 계약상 최대값인 1
   */
  public int getRetryCount() {
    return retryCount;
  }

  /**
   * 이 단계를 생성한 상태 변경 요청의 멱등 키를 반환한다.
   *
   * @return HTP 시작 또는 다음 단계 요청의 {@code Idempotency-Key}
   */
  public String getTransitionIdempotencyKey() {
    return transitionIdempotencyKey;
  }

  /**
   * 단계 생성 또는 완료에 사용된 멱등 키인지 확인한다.
   *
   * @param idempotencyKey 비교할 상태 변경 요청 키
   * @return 이 단계가 이미 처리한 키이면 {@code true}
   */
  public boolean hasProcessed(String idempotencyKey) {
    return transitionIdempotencyKey.equals(idempotencyKey)
        || Objects.equals(completionIdempotencyKey, idempotencyKey);
  }

  /**
   * 대화가 끝난 그림 세션을 리포트 없이 완료하고 요청 키를 기록한다.
   *
   * <p>PERSON은 다음 단계가 없어 완료 키를 다른 Entity에 남길 수 없으므로 단계 자체에 기록해 재시도를 멱등하게 처리한다.
   *
   * @param idempotencyKey 단계 완료 요청의 멱등 키
   * @param completedAt 서버가 결정한 UTC 기준 완료 시각
   */
  public void completeDrawingSession(String idempotencyKey, LocalDateTime completedAt) {
    Objects.requireNonNull(idempotencyKey, "idempotencyKey must not be null");
    Objects.requireNonNull(completedAt, "completedAt must not be null");
    if (idempotencyKey.equals(completionIdempotencyKey)) {
      return;
    }
    drawingSession.completeHtpStep(completedAt);
    completionIdempotencyKey = idempotencyKey;
  }
}
