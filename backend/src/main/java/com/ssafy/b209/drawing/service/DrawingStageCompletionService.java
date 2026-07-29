package com.ssafy.b209.drawing.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.domain.DrawingAnalysisTriggerReason;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.service.DrawingAnalysisPersistenceService;
import com.ssafy.b209.analysis.service.DrawingAnalysisRequestSummary;
import com.ssafy.b209.analysis.service.DrawingAnalysisService;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.dto.request.CompleteDrawingStageRequest;
import com.ssafy.b209.drawing.dto.request.UploadDrawingSnapshotRequest;
import com.ssafy.b209.drawing.dto.response.CompleteDrawingStageResponse;
import com.ssafy.b209.drawing.dto.response.DrawingStageAnalysisResponse;
import com.ssafy.b209.drawing.dto.response.UploadDrawingSnapshotResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.StoreImageCommand;
import java.util.Objects;
import java.util.Optional;
import org.springframework.stereotype.Service;

/**
 * 최종 그림 저장, 대화 준비용 객체 탐지와 그림 세션 단계 전환을 하나의 Use Case로 조율한다.
 *
 * <p>이미지 검증·저장은 {@link DrawingSnapshotService}, AI 호출과 분석 결과 저장은 {@link DrawingAnalysisService}에
 * 위임한다. 분석 실패 이력이 정상적으로 저장된 경우에는 최종 그림을 보존하고 감정 선택으로 진행할 수 있는 폴백 응답을 반환한다.
 */
@Service
public class DrawingStageCompletionService {

  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;
  private static final String NEXT_ACTION_SELECT_EMOTION = "SELECT_EMOTION";

  private final DrawingSnapshotService drawingSnapshotService;
  private final DrawingAssetRepository drawingAssetRepository;
  private final DrawingAnalysisService drawingAnalysisService;
  private final DrawingAnalysisPersistenceService analysisPersistenceService;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;

  /**
   * 그림 단계 완료에 필요한 저장·분석·인증 경계를 주입받는다.
   *
   * @param drawingSnapshotService FINAL 이미지 검증과 저장 서비스
   * @param drawingAssetRepository 기존 FINAL 그림 파일 조회 저장소
   * @param drawingAnalysisService 객체 탐지 실행 서비스
   * @param analysisPersistenceService 멱등 분석 상태 조회 서비스
   * @param currentUserResolver 현재 인증 사용자 식별자 Resolver
   * @param accessValidator 보호자의 그림 활동 접근 검증기
   */
  public DrawingStageCompletionService(
      DrawingSnapshotService drawingSnapshotService,
      DrawingAssetRepository drawingAssetRepository,
      DrawingAnalysisService drawingAnalysisService,
      DrawingAnalysisPersistenceService analysisPersistenceService,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this.drawingSnapshotService = drawingSnapshotService;
    this.drawingAssetRepository = drawingAssetRepository;
    this.drawingAnalysisService = drawingAnalysisService;
    this.analysisPersistenceService = analysisPersistenceService;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
  }

  /**
   * 그림 단계의 최종 이미지를 확정하고 대화 준비용 객체 탐지를 수행한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param idempotencyKey 완료 요청과 분석 실행을 함께 식별하는 Header 값
   * @param finalImage 최초 완료 요청에서 저장할 최종 이미지
   * @param request 클라이언트 완료 Metadata
   * @return FINAL 그림 파일, 분석 상태와 다음 동작
   * @throws BusinessException Header·Metadata·대상·상태가 유효하지 않거나 저장이 실패한 경우
   */
  public CompleteDrawingStageResponse complete(
      Long drawingSessionId,
      String idempotencyKey,
      StoreImageCommand finalImage,
      CompleteDrawingStageRequest request) {
    validateIdempotencyKey(idempotencyKey);
    validateRequest(request);
    requireAccess(drawingSessionId);

    Optional<DrawingAnalysisRequestSummary> existing =
        analysisPersistenceService.findByRequestId(idempotencyKey);
    if (existing.isPresent()) {
      return idempotentResponse(drawingSessionId, existing.get());
    }

    Long finalAssetId =
        request.sourceAssetId() == null
            ? findExistingFinalAsset(drawingSessionId)
                .orElseGet(() -> storeFinalImage(drawingSessionId, finalImage, request))
            : requireReusableSourceAsset(drawingSessionId, request.sourceAssetId());
    CreateDrawingAnalysisRequest analysisRequest =
        new CreateDrawingAnalysisRequest(
            finalAssetId,
            DrawingAnalysisType.OBJECT_DETECTION,
            DrawingAnalysisTriggerReason.DRAWING_COMPLETE);
    try {
      drawingAnalysisService.requestAnalysis(drawingSessionId, analysisRequest, idempotencyKey);
    } catch (BusinessException exception) {
      Optional<DrawingAnalysisRequestSummary> failed =
          analysisPersistenceService.findByRequestId(idempotencyKey);
      if (failed.isPresent() && failed.get().state() == DrawingAnalysisState.FAILED) {
        return idempotentResponse(drawingSessionId, failed.get());
      }
      throw exception;
    }

    DrawingAnalysisRequestSummary completed =
        analysisPersistenceService
            .findByRequestId(idempotencyKey)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_COMPLETION_CONFLICT));
    return idempotentResponse(drawingSessionId, completed);
  }

  private Long storeFinalImage(
      Long drawingSessionId, StoreImageCommand finalImage, CompleteDrawingStageRequest request) {
    if (finalImage == null) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_FILE_REQUIRED);
    }
    UploadDrawingSnapshotResponse stored =
        drawingSnapshotService.upload(
            drawingSessionId,
            finalImage,
            new UploadDrawingSnapshotRequest(
                DrawingAssetType.FINAL, 1, request.clientCompletedAt()));
    return stored.drawingAssetId();
  }

  private Long requireReusableSourceAsset(Long drawingSessionId, Long sourceAssetId) {
    DrawingAsset asset =
        drawingAssetRepository
            .findById(sourceAssetId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.FINAL_ASSET_REQUIRED));
    boolean reusableFinal = asset.getAssetType() == DrawingAssetType.FINAL;
    boolean reusableUpload =
        asset.getAssetType() == DrawingAssetType.UPLOADED
            && asset.getDrawingSession().getInputMethod() == DrawingInputMethod.UPLOAD;
    if (!Objects.equals(asset.getDrawingSession().getId(), drawingSessionId)
        || !reusableFinal && !reusableUpload) {
      throw new BusinessException(DrawingErrorCode.FINAL_ASSET_REQUIRED);
    }
    return asset.getId();
  }

  private Optional<Long> findExistingFinalAsset(Long drawingSessionId) {
    return drawingAssetRepository
        .findFirstByDrawingSessionIdAndAssetTypeOrderByAssetVersionDesc(
            drawingSessionId, DrawingAssetType.FINAL)
        .map(DrawingAsset::getId);
  }

  private CompleteDrawingStageResponse idempotentResponse(
      Long requestedSessionId, DrawingAnalysisRequestSummary summary) {
    if (!Objects.equals(summary.drawingSessionId(), requestedSessionId)
        || summary.taskType() != DrawingAnalysisType.OBJECT_DETECTION) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT);
    }
    if (summary.state() == DrawingAnalysisState.PROCESSING
        || summary.state() == DrawingAnalysisState.PENDING) {
      throw new BusinessException(DrawingErrorCode.DRAWING_COMPLETION_CONFLICT);
    }
    return new CompleteDrawingStageResponse(
        summary.drawingSessionId(),
        summary.drawingAssetId(),
        summary.sessionStatus(),
        summary.currentStage(),
        new DrawingStageAnalysisResponse(
            summary.analysisId(), summary.taskType(), DrawingAnalysisStatus.from(summary.state())),
        NEXT_ACTION_SELECT_EMOTION);
  }

  private void validateIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    }
    if (idempotencyKey.length() < IDEMPOTENCY_KEY_MIN_LENGTH
        || idempotencyKey.length() > IDEMPOTENCY_KEY_MAX_LENGTH
        || idempotencyKey.isBlank()
        || idempotencyKey.chars().anyMatch(Character::isISOControl)) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    }
  }

  private void validateRequest(CompleteDrawingStageRequest request) {
    if (request == null
        || request.drawingDurationMs() == null
        || request.drawingDurationMs() <= 0
        || request.clientCompletedAt() == null
        || request.sourceAssetId() != null && request.sourceAssetId() <= 0
        || request.lastEventSequence() != null && request.lastEventSequence() < 0) {
      throw new BusinessException(DrawingErrorCode.DRAWING_SNAPSHOT_METADATA_INVALID);
    }
  }

  private void requireAccess(Long drawingSessionId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
  }
}
