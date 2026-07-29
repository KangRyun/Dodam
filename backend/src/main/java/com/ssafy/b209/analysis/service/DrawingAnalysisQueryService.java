package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.AnalysisBoundingBoxResponse;
import com.ssafy.b209.analysis.dto.AnalysisDetectedObjectResponse;
import com.ssafy.b209.analysis.dto.AnalysisStatusResponse;
import com.ssafy.b209.analysis.dto.BoundingBoxResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisDetailResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisFailureResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisHistoryResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisModelResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 저장된 그림 분석 상태와 객체 탐지 결과를 공개 조회 계약으로 변환한다.
 *
 * <p>조회 시 AI Client나 파일 저장소를 호출하지 않으며 상태와 결과의 저장 정합성을 검증한다.
 */
@Service
public class DrawingAnalysisQueryService {

  private static final String FAILURE_CODE = "AI_ANALYSIS_FAILED";
  private static final String FAILURE_MESSAGE = "그림 분석 처리에 실패했습니다.";

  private final DrawingAnalysisRepository drawingAnalysisRepository;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;

  /**
   * 분석 조회에 사용할 Repository를 주입받는다.
   *
   * @param drawingAnalysisRepository Session과 결과를 함께 조회하는 Repository
   * @param currentUserResolver Access Token에서 현재 사용자 ID를 제공하는 Resolver
   * @param accessValidator 보호자와 그림 활동의 연결 관계를 검증하는 Validator
   */
  public DrawingAnalysisQueryService(
      DrawingAnalysisRepository drawingAnalysisRepository,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this.drawingAnalysisRepository = drawingAnalysisRepository;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
  }

  /**
   * 요청한 Session에 속한 분석의 현재 상태와 저장된 Detection을 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param drawingAnalysisId 분석 실행 식별자
   * @return 상태별 규칙에 맞게 조립된 분석 상세 응답
   * @throws BusinessException 분석이 없거나 저장 데이터가 상태 규칙과 모순되는 경우
   */
  @Transactional(readOnly = true)
  public DrawingAnalysisDetailResponse getDrawingAnalysis(
      Long drawingSessionId, Long drawingAnalysisId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    DrawingAnalysis analysis =
        drawingAnalysisRepository
            .findDetailBySessionIdAndAnalysisId(drawingSessionId, drawingAnalysisId)
            .orElseThrow(
                () -> new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_FOUND));

    validateCommonFields(analysis);
    return switch (analysis.getState()) {
      case PENDING -> inProgressResponse(analysis, DrawingAnalysisStatus.PENDING);
      case PROCESSING -> inProgressResponse(analysis, DrawingAnalysisStatus.PROCESSING);
      case SUCCESS, PARTIAL_SUCCESS -> successResponse(analysis);
      case FAILED -> failureResponse(analysis);
    };
  }

  /**
   * 분석 식별자로 현재 상태와 보호자에게 공개 가능한 결과를 조회한다.
   *
   * <p>분석에서 Session을 역참조한 뒤 연결 보호자 권한을 검증한다. 기존 세션 하위 조회와 달리 DB의 {@code SUCCESS}와 {@code
   * PARTIAL_SUCCESS}를 구분해 그대로 반환한다.
   *
   * @param analysisId 분석 실행 식별자
   * @return 정본 공개 계약에 맞게 조립한 분석 상태 응답
   * @throws BusinessException 분석이 없거나 접근 권한 또는 저장 결과 정합성 검증에 실패한 경우
   */
  @Transactional(readOnly = true)
  public AnalysisStatusResponse getAnalysisStatus(Long analysisId) {
    DrawingAnalysis analysis =
        drawingAnalysisRepository
            .findDetailByAnalysisId(analysisId)
            .orElseThrow(
                () -> new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_FOUND));
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(
        guardianUserId, analysis.getDrawingSession().getId());
    validateCommonFields(analysis);

    return switch (analysis.getState()) {
      case PENDING, PROCESSING -> canonicalInProgressResponse(analysis);
      case SUCCESS, PARTIAL_SUCCESS -> canonicalSuccessResponse(analysis);
      case FAILED -> canonicalFailureResponse(analysis);
    };
  }

  /**
   * 요청한 세션의 그림 분석 이력을 요청 시각 역순으로 조회한다.
   *
   * <p>객체 탐지 결과는 포함하지 않고 상태 요약만 반환하며 조회 과정에서 상태를 변경하지 않는다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 요청 시각 역순의 분석 이력 목록, 없으면 빈 목록
   * @throws BusinessException 접근할 수 없거나 삭제된 세션인 경우
   */
  @Transactional(readOnly = true)
  public List<DrawingAnalysisHistoryResponse> getDrawingAnalyses(Long drawingSessionId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    return drawingAnalysisRepository
        .findAllByDrawingSessionIdOrderByRequestedAtDescIdDesc(drawingSessionId)
        .stream()
        .map(this::toHistory)
        .toList();
  }

  private DrawingAnalysisHistoryResponse toHistory(DrawingAnalysis analysis) {
    return new DrawingAnalysisHistoryResponse(
        analysis.getId(),
        analysis.getDrawingAsset().getId(),
        analysis.getScope(),
        analysis.getTaskType(),
        analysis.getState(),
        toInstant(analysis.getRequestedAt()),
        analysis.getCompletedAt() == null ? null : toInstant(analysis.getCompletedAt()));
  }

  private DrawingAnalysisDetailResponse inProgressResponse(
      DrawingAnalysis analysis, DrawingAnalysisStatus status) {
    if (hasModel(analysis)
        || hasFailure(analysis)
        || analysis.getCompletedAt() != null
        || !analysis.getDetections().isEmpty()) {
      throw inconsistent();
    }
    return response(analysis, status, null, List.of(), null, null);
  }

  private DrawingAnalysisDetailResponse successResponse(DrawingAnalysis analysis) {
    if (!hasCompleteModel(analysis) || hasFailure(analysis) || analysis.getCompletedAt() == null) {
      throw inconsistent();
    }
    DrawingAnalysisModelResponse model =
        new DrawingAnalysisModelResponse(analysis.getModelName(), analysis.getModelVersion());
    List<DrawingDetectionResponse> detections =
        analysis.getDetections().stream().map(this::detectionResponse).toList();
    return response(
        analysis,
        DrawingAnalysisStatus.SUCCEEDED,
        model,
        detections,
        toInstant(analysis.getCompletedAt()),
        null);
  }

  private DrawingAnalysisDetailResponse failureResponse(DrawingAnalysis analysis) {
    if (hasModel(analysis)
        || !hasCompleteFailure(analysis)
        || analysis.getCompletedAt() == null
        || !analysis.getDetections().isEmpty()) {
      throw inconsistent();
    }
    return response(
        analysis,
        DrawingAnalysisStatus.FAILED,
        null,
        List.of(),
        toInstant(analysis.getCompletedAt()),
        new DrawingAnalysisFailureResponse(FAILURE_CODE, FAILURE_MESSAGE));
  }

  private AnalysisStatusResponse canonicalInProgressResponse(DrawingAnalysis analysis) {
    if (hasModel(analysis)
        || hasFailure(analysis)
        || analysis.getCompletedAt() != null
        || !analysis.getDetections().isEmpty()) {
      throw inconsistent();
    }
    return canonicalResponse(analysis, List.of(), null, null);
  }

  private AnalysisStatusResponse canonicalSuccessResponse(DrawingAnalysis analysis) {
    if (!hasCompleteModel(analysis) || hasFailure(analysis) || analysis.getCompletedAt() == null) {
      throw inconsistent();
    }
    return canonicalResponse(
        analysis,
        analysis.getDetections().stream()
            .map(detection -> canonicalDetection(analysis, detection))
            .toList(),
        null,
        null);
  }

  private AnalysisStatusResponse canonicalFailureResponse(DrawingAnalysis analysis) {
    if (hasModel(analysis)
        || !hasCompleteFailure(analysis)
        || analysis.getCompletedAt() == null
        || !analysis.getDetections().isEmpty()) {
      throw inconsistent();
    }
    return canonicalResponse(analysis, List.of(), FAILURE_CODE, FAILURE_MESSAGE);
  }

  private AnalysisStatusResponse canonicalResponse(
      DrawingAnalysis analysis,
      List<AnalysisDetectedObjectResponse> detectedObjects,
      String failureCode,
      String message) {
    return new AnalysisStatusResponse(
        analysis.getId(),
        analysis.getDrawingSession().getId(),
        analysis.getDrawingAsset().getId(),
        analysis.getScope(),
        analysis.getTaskType(),
        analysis.getState(),
        analysis.getConfidence(),
        analysis.getModelName(),
        analysis.getModelVersion(),
        toInstant(analysis.getRequestedAt()),
        analysis.getCompletedAt() == null ? null : toInstant(analysis.getCompletedAt()),
        detectedObjects,
        failureCode,
        message);
  }

  private AnalysisDetectedObjectResponse canonicalDetection(
      DrawingAnalysis analysis, DrawingDetectedObject detection) {
    DrawingAssetDimensions dimensions =
        new DrawingAssetDimensions(
            analysis.getDrawingAsset().getWidthPx(), analysis.getDrawingAsset().getHeightPx());
    return new AnalysisDetectedObjectResponse(
        detection.getId(),
        detection.getLabel(),
        detection.getObjectName(),
        detection.getConfidence(),
        normalizedBoundingBox(detection, dimensions));
  }

  private AnalysisBoundingBoxResponse normalizedBoundingBox(
      DrawingDetectedObject detection, DrawingAssetDimensions dimensions) {
    if (detection.getCoordinateSpace()
        == com.ssafy.b209.analysis.domain.DrawingCoordinateSpace.NORMALIZED) {
      return new AnalysisBoundingBoxResponse(
          detection.getX(), detection.getY(), detection.getWidth(), detection.getHeight());
    }
    if (!dimensions.isAvailable()) {
      throw inconsistent();
    }
    BigDecimal imageWidth = BigDecimal.valueOf(dimensions.widthPx());
    BigDecimal imageHeight = BigDecimal.valueOf(dimensions.heightPx());
    return new AnalysisBoundingBoxResponse(
        detection.getX().divide(imageWidth, 6, java.math.RoundingMode.HALF_UP),
        detection.getY().divide(imageHeight, 6, java.math.RoundingMode.HALF_UP),
        detection.getWidth().divide(imageWidth, 6, java.math.RoundingMode.HALF_UP),
        detection.getHeight().divide(imageHeight, 6, java.math.RoundingMode.HALF_UP));
  }

  private record DrawingAssetDimensions(Integer widthPx, Integer heightPx) {

    private boolean isAvailable() {
      return widthPx != null && widthPx > 0 && heightPx != null && heightPx > 0;
    }
  }

  private DrawingAnalysisDetailResponse response(
      DrawingAnalysis analysis,
      DrawingAnalysisStatus status,
      DrawingAnalysisModelResponse model,
      List<DrawingDetectionResponse> detections,
      Instant processedAt,
      DrawingAnalysisFailureResponse failure) {
    return new DrawingAnalysisDetailResponse(
        analysis.getId(),
        analysis.getDrawingSession().getId(),
        analysis.getDrawingAsset().getId(),
        analysis.getRequestId(),
        analysis.getTaskType(),
        status,
        model,
        detections,
        toInstant(analysis.getRequestedAt()),
        processedAt,
        failure);
  }

  private DrawingDetectionResponse detectionResponse(DrawingDetectedObject detection) {
    if (!hasText(detection.getLabel())
        || !betweenZeroAndOne(detection.getConfidence())
        || !atLeastZero(detection.getX())
        || !atLeastZero(detection.getY())
        || !greaterThanZero(detection.getWidth())
        || !greaterThanZero(detection.getHeight())
        || detection.getDisplayOrder() < 0) {
      throw inconsistent();
    }
    return new DrawingDetectionResponse(
        detection.getLabel(),
        detection.getConfidence(),
        new BoundingBoxResponse(
            detection.getX(), detection.getY(), detection.getWidth(), detection.getHeight()));
  }

  private void validateCommonFields(DrawingAnalysis analysis) {
    if (analysis.getId() == null
        || analysis.getDrawingSession() == null
        || analysis.getDrawingSession().getId() == null
        || analysis.getDrawingAsset() == null
        || analysis.getDrawingAsset().getId() == null
        || analysis.getDrawingAsset().getDrawingSession() == null
        || !analysis
            .getDrawingSession()
            .getId()
            .equals(analysis.getDrawingAsset().getDrawingSession().getId())
        || analysis.getTaskType() == null
        || analysis.getState() == null
        || !hasText(analysis.getRequestId())
        || analysis.getRequestedAt() == null) {
      throw inconsistent();
    }
  }

  private boolean hasModel(DrawingAnalysis analysis) {
    return analysis.getModelName() != null || analysis.getModelVersion() != null;
  }

  private boolean hasCompleteModel(DrawingAnalysis analysis) {
    return hasText(analysis.getModelName()) && hasText(analysis.getModelVersion());
  }

  private boolean hasFailure(DrawingAnalysis analysis) {
    return analysis.getErrorCode() != null || analysis.getErrorMessage() != null;
  }

  private boolean hasCompleteFailure(DrawingAnalysis analysis) {
    return hasText(analysis.getErrorCode()) && hasText(analysis.getErrorMessage());
  }

  private boolean hasText(String value) {
    return value != null && !value.isBlank();
  }

  private boolean betweenZeroAndOne(BigDecimal value) {
    return value != null
        && value.compareTo(BigDecimal.ZERO) >= 0
        && value.compareTo(BigDecimal.ONE) <= 0;
  }

  private boolean atLeastZero(BigDecimal value) {
    return value != null && value.compareTo(BigDecimal.ZERO) >= 0;
  }

  private boolean greaterThanZero(BigDecimal value) {
    return value != null && value.compareTo(BigDecimal.ZERO) > 0;
  }

  private Instant toInstant(LocalDateTime value) {
    return value.toInstant(ZoneOffset.UTC);
  }

  private BusinessException inconsistent() {
    return new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_INCONSISTENT);
  }
}
