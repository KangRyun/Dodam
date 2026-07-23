package com.ssafy.b209.analysis.domain;

import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
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
 * 그림 파일에 대한 단일 AI 분석 실행의 상태와 저장된 객체 탐지 결과를 관리한다.
 *
 * <p>기존 DB 상태 {@code SUCCESS}를 유지하며 외부 계약의 {@code SUCCEEDED} 변환은 Application Service에서 담당한다.
 */
@Entity
@Table(name = "analyses")
public class DrawingAnalysis {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_session_id", nullable = false)
  private DrawingSession drawingSession;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_asset_id", nullable = false)
  private DrawingAsset drawingAsset;

  @Enumerated(EnumType.STRING)
  @Column(name = "analysis_type", nullable = false, length = 20)
  private DrawingAnalysisScope scope;

  @Enumerated(EnumType.STRING)
  @Column(name = "analysis_task_type", nullable = false, length = 30)
  private DrawingAnalysisType taskType;

  @Column(name = "idempotency_key", nullable = false, length = 100, unique = true)
  private String requestId;

  @Enumerated(EnumType.STRING)
  @Column(name = "analysis_status", nullable = false, length = 20)
  private DrawingAnalysisState state;

  @Column(name = "trigger_reason", length = 30)
  private String triggerReason;

  @Column(name = "model_name", length = 100)
  private String modelName;

  @Column(name = "model_version", length = 100)
  private String modelVersion;

  @Column(name = "error_code", length = 80)
  private String errorCode;

  @Column(name = "error_message")
  private String errorMessage;

  @Column(name = "requested_at", nullable = false)
  private LocalDateTime requestedAt;

  @Column(name = "started_at")
  private LocalDateTime startedAt;

  @Column(name = "completed_at")
  private LocalDateTime completedAt;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @OneToMany(mappedBy = "drawingAnalysis", cascade = CascadeType.ALL, orphanRemoval = true)
  @OrderBy("displayOrder ASC, id ASC")
  private List<DrawingDetectedObject> detections = new ArrayList<>();

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected DrawingAnalysis() {}

  private DrawingAnalysis(
      DrawingSession drawingSession,
      DrawingAsset drawingAsset,
      DrawingAnalysisScope scope,
      DrawingAnalysisType taskType,
      String requestId,
      LocalDateTime requestedAt) {
    this.drawingSession = Objects.requireNonNull(drawingSession, "drawingSession must not be null");
    this.drawingAsset = Objects.requireNonNull(drawingAsset, "drawingAsset must not be null");
    this.scope = Objects.requireNonNull(scope, "scope must not be null");
    this.taskType = Objects.requireNonNull(taskType, "taskType must not be null");
    this.requestId = requireText(requestId, "requestId");
    this.state = DrawingAnalysisState.PROCESSING;
    this.triggerReason = "USER_REQUEST";
    this.requestedAt = Objects.requireNonNull(requestedAt, "requestedAt must not be null");
    this.startedAt = requestedAt;
    this.createdAt = requestedAt;
  }

  /**
   * 사용자 요청으로 즉시 실행을 시작하는 분석 이력을 생성한다.
   *
   * @param drawingSession 분석 대상 그림 활동 세션
   * @param drawingAsset 분석 대상 그림 파일
   * @param scope 기존 ERD에서 사용하는 중간 또는 최종 분석 시점
   * @param taskType 수행할 AI 분석 작업 유형
   * @param requestId Client 요청과 응답을 연결하는 서버 생성 UUID
   * @param requestedAt 서버가 요청을 시작한 UTC 시각
   * @return {@link DrawingAnalysisState#PROCESSING} 상태의 분석 실행
   */
  public static DrawingAnalysis processing(
      DrawingSession drawingSession,
      DrawingAsset drawingAsset,
      DrawingAnalysisScope scope,
      DrawingAnalysisType taskType,
      String requestId,
      LocalDateTime requestedAt) {
    return new DrawingAnalysis(
        drawingSession, drawingAsset, scope, taskType, requestId, requestedAt);
  }

  /**
   * 그림 활동 완료 후 비동기 처리를 기다리는 최종 분석 요청을 생성한다.
   *
   * <p>외부 AI 처리를 아직 시작하지 않았으므로 {@code startedAt}과 {@code completedAt}은 기록하지 않는다.
   *
   * @param drawingSession 분석 대상 그림 활동 세션
   * @param drawingAsset 분석 대상 최종 그림
   * @param taskType 수행할 최종 분석 작업 유형
   * @param idempotencyKey 완료 접수 요청을 식별하는 멱등 키
   * @param requestedAt 서버가 요청을 접수한 UTC 시각
   * @return {@link DrawingAnalysisState#PENDING} 상태의 최종 분석 요청
   */
  public static DrawingAnalysis pending(
      DrawingSession drawingSession,
      DrawingAsset drawingAsset,
      DrawingAnalysisType taskType,
      String idempotencyKey,
      LocalDateTime requestedAt) {
    DrawingAnalysis analysis = new DrawingAnalysis();
    analysis.drawingSession =
        Objects.requireNonNull(drawingSession, "drawingSession must not be null");
    analysis.drawingAsset = Objects.requireNonNull(drawingAsset, "drawingAsset must not be null");
    analysis.scope = DrawingAnalysisScope.FINAL;
    analysis.taskType = Objects.requireNonNull(taskType, "taskType must not be null");
    analysis.requestId = requireText(idempotencyKey, "idempotencyKey");
    analysis.state = DrawingAnalysisState.PENDING;
    analysis.triggerReason = "ACTIVITY_COMPLETE";
    analysis.requestedAt = Objects.requireNonNull(requestedAt, "requestedAt must not be null");
    analysis.createdAt = requestedAt;
    return analysis;
  }

  /**
   * 유효한 AI 결과와 Detection을 연결하고 분석을 성공 상태로 전환한다.
   *
   * @param modelName 분석에 사용한 Model 이름
   * @param modelVersion 분석에 사용한 Model 버전
   * @param detectedObjects 저장할 객체 탐지 결과이며 빈 목록을 허용함
   * @param processedAt 분석 처리가 끝난 UTC 시각
   * @throws IllegalStateException 현재 상태가 PROCESSING이 아닌 경우
   */
  public void succeed(
      String modelName,
      String modelVersion,
      List<DrawingDetectedObject> detectedObjects,
      LocalDateTime processedAt) {
    ensureProcessing();
    this.modelName = requireText(modelName, "modelName");
    this.modelVersion = requireText(modelVersion, "modelVersion");
    Objects.requireNonNull(detectedObjects, "detectedObjects must not be null")
        .forEach(
            detection -> {
              Objects.requireNonNull(detection, "detection must not be null").attachTo(this);
              detections.add(detection);
            });
    this.state = DrawingAnalysisState.SUCCESS;
    this.completedAt = Objects.requireNonNull(processedAt, "processedAt must not be null");
    this.errorCode = null;
    this.errorMessage = null;
  }

  /**
   * 외부에 노출해도 되는 오류 정보만 기록하고 분석을 실패 상태로 전환한다.
   *
   * @param failureCode 내부 분류에 사용하는 안전한 오류 코드
   * @param failureMessage 원문 예외를 포함하지 않는 안전한 오류 메시지
   * @param failedAt 실패 처리가 끝난 UTC 시각
   * @throws IllegalStateException 현재 상태가 PROCESSING이 아닌 경우
   */
  public void fail(String failureCode, String failureMessage, LocalDateTime failedAt) {
    ensureProcessing();
    this.state = DrawingAnalysisState.FAILED;
    this.errorCode = requireText(failureCode, "failureCode");
    this.errorMessage = requireText(failureMessage, "failureMessage");
    this.completedAt = Objects.requireNonNull(failedAt, "failedAt must not be null");
  }

  /**
   * @return 분석 실행 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 분석 대상 그림 활동 세션
   */
  public DrawingSession getDrawingSession() {
    return drawingSession;
  }

  /**
   * @return 분석 대상 그림 파일
   */
  public DrawingAsset getDrawingAsset() {
    return drawingAsset;
  }

  /**
   * @return 서버가 생성한 분석 요청 UUID
   */
  public String getRequestId() {
    return requestId;
  }

  /**
   * @return 수행한 AI 분석 작업 유형
   */
  public DrawingAnalysisType getTaskType() {
    return taskType;
  }

  /**
   * 분석이 중간 그림과 최종 그림 중 어느 범위에 해당하는지 반환한다.
   *
   * @return 분석 대상 범위
   */
  public DrawingAnalysisScope getScope() {
    return scope;
  }

  /**
   * @return DB에 저장되는 현재 분석 상태
   */
  public DrawingAnalysisState getState() {
    return state;
  }

  /**
   * @return 성공한 분석의 Model 이름
   */
  public String getModelName() {
    return modelName;
  }

  /**
   * @return 성공한 분석의 Model 버전
   */
  public String getModelVersion() {
    return modelVersion;
  }

  /**
   * @return 실패 분류 코드
   */
  public String getErrorCode() {
    return errorCode;
  }

  /**
   * @return 안전하게 정제된 실패 메시지
   */
  public String getErrorMessage() {
    return errorMessage;
  }

  /**
   * @return 서버가 분석 요청을 시작한 UTC 시각
   */
  public LocalDateTime getRequestedAt() {
    return requestedAt;
  }

  /**
   * 외부 분석 처리를 실제로 시작한 시각을 반환한다.
   *
   * @return 처리를 시작하기 전이면 {@code null}
   */
  public LocalDateTime getStartedAt() {
    return startedAt;
  }

  /**
   * @return 성공 또는 실패 처리가 끝난 UTC 시각
   */
  public LocalDateTime getCompletedAt() {
    return completedAt;
  }

  /**
   * @return 수정할 수 없는 객체 탐지 결과 목록
   */
  public List<DrawingDetectedObject> getDetections() {
    return Collections.unmodifiableList(detections);
  }

  private void ensureProcessing() {
    if (state != DrawingAnalysisState.PROCESSING) {
      throw new IllegalStateException("only processing analysis can be completed");
    }
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
