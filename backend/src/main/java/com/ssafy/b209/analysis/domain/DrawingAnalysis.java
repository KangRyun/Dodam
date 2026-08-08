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
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * 그림 파일에 대한 단일 AI 분석 실행의 상태와 저장된 객체 탐지 결과를 관리한다.
 *
 * <p>기존 세션 하위 조회의 {@code SUCCEEDED} 호환 변환과 정본 상태 조회의 DB 상태 보존은 Application Service에서 각각 담당한다.
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

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "retry_of_analysis_id")
  private DrawingAnalysis retryOfAnalysis;

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

  @Column(name = "model_version", length = 255)
  private String modelVersion;

  @Column(name = "confidence", precision = 5, scale = 4)
  private BigDecimal confidence;

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
      DrawingAnalysisTriggerReason triggerReason,
      LocalDateTime requestedAt) {
    this.drawingSession = Objects.requireNonNull(drawingSession, "drawingSession must not be null");
    this.drawingAsset = Objects.requireNonNull(drawingAsset, "drawingAsset must not be null");
    this.scope = Objects.requireNonNull(scope, "scope must not be null");
    this.taskType = Objects.requireNonNull(taskType, "taskType must not be null");
    this.requestId = requireText(requestId, "requestId");
    this.state = DrawingAnalysisState.PROCESSING;
    this.triggerReason =
        Objects.requireNonNull(triggerReason, "triggerReason must not be null").name();
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
        drawingSession,
        drawingAsset,
        scope,
        taskType,
        requestId,
        DrawingAnalysisTriggerReason.USER_REQUEST,
        requestedAt);
  }

  /**
   * 요청에서 확정한 실행 사유와 함께 즉시 수행할 분석을 생성한다.
   *
   * @param drawingSession 분석 대상 그림 세션
   * @param drawingAsset 분석 대상 그림 파일
   * @param scope 중간 또는 최종 분석 범위
   * @param taskType 수행할 분석 작업 유형
   * @param requestId 요청 추적 식별자
   * @param triggerReason 분석을 시작한 실제 계기
   * @param requestedAt 서버가 요청을 시작한 UTC 시각
   * @return 처리 중인 분석
   */
  public static DrawingAnalysis processing(
      DrawingSession drawingSession,
      DrawingAsset drawingAsset,
      DrawingAnalysisScope scope,
      DrawingAnalysisType taskType,
      String requestId,
      DrawingAnalysisTriggerReason triggerReason,
      LocalDateTime requestedAt) {
    return new DrawingAnalysis(
        drawingSession, drawingAsset, scope, taskType, requestId, triggerReason, requestedAt);
  }

  /**
   * 실패한 원본 분석과 연결된 새 분석 실행을 생성한다.
   *
   * @param source 실패한 원본 분석
   * @param drawingAsset 재시도에 사용할 원본 또는 최신 그림 파일
   * @param requestId 새 AI 요청을 식별하는 서버 생성 UUID
   * @param requestedAt 서버가 재시도를 시작한 UTC 시각
   * @return 원본 분석과 연결된 {@link DrawingAnalysisState#PROCESSING} 실행
   */
  public static DrawingAnalysis processingRetry(
      DrawingAnalysis source,
      DrawingAsset drawingAsset,
      String requestId,
      LocalDateTime requestedAt) {
    Objects.requireNonNull(source, "source must not be null");
    DrawingAnalysis retry =
        new DrawingAnalysis(
            source.drawingSession,
            drawingAsset,
            source.scope,
            source.taskType,
            requestId,
            DrawingAnalysisTriggerReason.RETRY,
            requestedAt);
    retry.retryOfAnalysis = source;
    retry.triggerReason = "RETRY";
    return retry;
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
   * 실패한 최종 분석을 원본으로 연결한 리포트 재생성용 분석 요청을 만든다.
   *
   * <p>원본 분석의 Drawing Session과 작업 유형을 유지하면서 세션의 최신 최종 그림을 사용할 수 있게 한다. 원본 결과는 변경하지 않고 {@code
   * retry_of_analysis_id} 관계로 재시도 이력을 보존한다.
   *
   * <p>원본은 Report의 지연 로딩 연관에서 넘어올 수 있으므로 Field가 아니라 Getter로 읽는다. 초기화되지 않은 Proxy의 Field는 비어 있어 재시도
   * 자격 검증이 잘못 실패한다.
   *
   * @param source 실패한 원본 최종 분석
   * @param drawingAsset 재생성에 사용할 최종 그림 Asset
   * @param idempotencyKey 재생성 요청을 식별하는 멱등 키
   * @param requestedAt 서버가 재생성을 접수한 UTC 시각
   * @return {@link DrawingAnalysisState#PENDING} 상태의 새 최종 분석
   * @throws IllegalArgumentException 원본이 FAILED 상태의 FINAL ACTIVITY_REPORT 분석이 아닌 경우
   */
  public static DrawingAnalysis pendingRetry(
      DrawingAnalysis source,
      DrawingAsset drawingAsset,
      String idempotencyKey,
      LocalDateTime requestedAt) {
    Objects.requireNonNull(source, "source must not be null");
    if (source.getState() != DrawingAnalysisState.FAILED
        || source.getScope() != DrawingAnalysisScope.FINAL
        || source.getTaskType() != DrawingAnalysisType.ACTIVITY_REPORT) {
      throw new IllegalArgumentException("source must be a failed final activity report analysis");
    }
    DrawingAnalysis retry =
        pending(
            source.getDrawingSession(),
            drawingAsset,
            source.getTaskType(),
            idempotencyKey,
            requestedAt);
    retry.retryOfAnalysis = source;
    retry.triggerReason = "RETRY";
    return retry;
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
    complete(DrawingAnalysisState.SUCCESS, modelName, modelVersion, detectedObjects, processedAt);
  }

  /**
   * AI 종합 분석 결과를 Detection과 연결하고 전체 또는 부분 성공 상태로 전환한다.
   *
   * @param completedState {@link DrawingAnalysisState#SUCCESS} 또는 {@link
   *     DrawingAnalysisState#PARTIAL_SUCCESS}
   * @param modelName 대표 객체 탐지 Model 이름
   * @param modelVersion 대표 객체 탐지 Model 버전
   * @param detectedObjects 저장할 객체 탐지 결과
   * @param processedAt 분석 처리가 끝난 UTC 시각
   * @throws IllegalArgumentException 완료 상태가 성공 상태가 아니거나 Model 정보가 유효하지 않은 경우
   * @throws IllegalStateException 현재 상태가 PROCESSING이 아닌 경우
   */
  public void complete(
      DrawingAnalysisState completedState,
      String modelName,
      String modelVersion,
      List<DrawingDetectedObject> detectedObjects,
      LocalDateTime processedAt) {
    ensureProcessing();
    if (completedState != DrawingAnalysisState.SUCCESS
        && completedState != DrawingAnalysisState.PARTIAL_SUCCESS) {
      throw new IllegalArgumentException("completedState must be a success state");
    }
    this.modelName = requireText(modelName, "modelName");
    this.modelVersion = requireText(modelVersion, "modelVersion");
    Objects.requireNonNull(detectedObjects, "detectedObjects must not be null")
        .forEach(
            detection -> {
              Objects.requireNonNull(detection, "detection must not be null").attachTo(this);
              detections.add(detection);
            });
    this.state = completedState;
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
   * 완료 접수로 대기 중인 최종 분석을 성공 상태로 전환한다.
   *
   * @param modelName 최종 분석에 사용한 Model 이름
   * @param modelVersion 최종 분석에 사용한 Model 버전
   * @param confidence 0 이상 1 이하의 신뢰도이며 없으면 {@code null}
   * @param completedAt 최종 분석 처리가 끝난 UTC 시각
   * @throws IllegalStateException 현재 상태가 PENDING이 아닌 경우
   * @throws IllegalArgumentException 신뢰도가 허용 범위를 벗어난 경우
   */
  public void succeedFinal(
      String modelName, String modelVersion, BigDecimal confidence, LocalDateTime completedAt) {
    ensurePending();
    this.modelName = requireText(modelName, "modelName");
    this.modelVersion = requireText(modelVersion, "modelVersion");
    this.confidence = requireConfidence(confidence);
    this.state = DrawingAnalysisState.SUCCESS;
    this.startedAt = this.startedAt == null ? completedAt : this.startedAt;
    this.completedAt = Objects.requireNonNull(completedAt, "completedAt must not be null");
    this.errorCode = null;
    this.errorMessage = null;
  }

  /**
   * 완료 접수로 대기 중인 최종 분석을 실패 상태로 전환한다.
   *
   * @param failureCode 내부 분류에 사용하는 안전한 오류 코드
   * @param failureMessage 원문 예외를 포함하지 않는 안전한 오류 메시지
   * @param failedAt 실패 처리가 끝난 UTC 시각
   * @throws IllegalStateException 현재 상태가 PENDING이 아닌 경우
   */
  public void failFinal(String failureCode, String failureMessage, LocalDateTime failedAt) {
    ensurePending();
    this.state = DrawingAnalysisState.FAILED;
    this.errorCode = requireText(failureCode, "failureCode");
    this.errorMessage = requireText(failureMessage, "failureMessage");
    this.startedAt = this.startedAt == null ? failedAt : this.startedAt;
    this.completedAt = Objects.requireNonNull(failedAt, "failedAt must not be null");
  }

  /**
   * 실패한 최종 분석을 다시 대기 상태로 되돌린다 (S15P11B209 P0-2).
   *
   * <p>리포트 재시도 워커만 부른다. 실패 코드와 메시지를 지우는 이유는 <strong>다음 시도가 다른 이유로 실패할 수 있기 때문</strong>이다 — 남겨 두면
   * 두 번째 실패의 원인을 첫 번째 실패의 코드로 읽게 된다. 지난 시도 기록은 {@code report_generation_retries} 행에 남는다.
   *
   * @throws IllegalStateException 실패 상태가 아닌 경우
   */
  public void reopenForRetry() {
    if (state != DrawingAnalysisState.FAILED) {
      throw new IllegalStateException("only failed analysis can be reopened");
    }
    this.state = DrawingAnalysisState.PENDING;
    this.errorCode = null;
    this.errorMessage = null;
    this.completedAt = null;
  }

  /**
   * @return 대기 중인 최종 분석이면 {@code true}
   */
  public boolean isPending() {
    return state == DrawingAnalysisState.PENDING;
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
   * 재시도 원본 분석을 반환한다.
   *
   * @return 최초 요청이면 {@code null}, 재시도이면 원본 분석
   */
  public DrawingAnalysis getRetryOfAnalysis() {
    return retryOfAnalysis;
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
   * @return 분석 실행을 시작한 실제 계기
   */
  public DrawingAnalysisTriggerReason getTriggerReason() {
    return DrawingAnalysisTriggerReason.valueOf(triggerReason);
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

  /**
   * @return 성공한 최종 분석의 신뢰도이며 기록하지 않았으면 {@code null}
   */
  public BigDecimal getConfidence() {
    return confidence;
  }

  private void ensureProcessing() {
    if (state != DrawingAnalysisState.PROCESSING) {
      throw new IllegalStateException("only processing analysis can be completed");
    }
  }

  private void ensurePending() {
    if (state != DrawingAnalysisState.PENDING) {
      throw new IllegalStateException("only pending final analysis can change its result state");
    }
  }

  private static BigDecimal requireConfidence(BigDecimal value) {
    if (value == null) {
      return null;
    }
    if (value.compareTo(BigDecimal.ZERO) < 0 || value.compareTo(BigDecimal.ONE) > 0) {
      throw new IllegalArgumentException("confidence is out of range");
    }
    return value;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }
}
