package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 그림 분석의 시작, 성공과 실패 상태를 서로 독립된 짧은 Transaction으로 저장한다.
 *
 * <p>AI Client 호출은 이 클래스 밖에서 수행하므로 외부 통신 실패가 시작 행을 Rollback하지 않는다.
 */
@Service
public class DrawingAnalysisPersistenceService {

  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingAssetRepository drawingAssetRepository;
  private final DrawingAnalysisRepository drawingAnalysisRepository;

  /**
   * 분석 저장에 필요한 Repository를 주입받는다.
   *
   * @param drawingSessionRepository 분석 가능 세션 조회와 잠금 저장소
   * @param drawingAssetRepository 분석 대상 그림 파일 저장소
   * @param drawingAnalysisRepository 분석 실행 저장소
   */
  public DrawingAnalysisPersistenceService(
      DrawingSessionRepository drawingSessionRepository,
      DrawingAssetRepository drawingAssetRepository,
      DrawingAnalysisRepository drawingAnalysisRepository) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingAssetRepository = drawingAssetRepository;
    this.drawingAnalysisRepository = drawingAnalysisRepository;
  }

  /**
   * 세션과 허용된 그림 파일의 관계 및 중복을 검증하고 PROCESSING 분석 행을 저장한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param drawingAssetId 분석 대상 그림 파일 식별자
   * @param taskType 수행할 AI 분석 작업 유형
   * @param requestId 서버가 생성한 요청 UUID
   * @param requestedAt 서버가 분석 요청을 시작한 UTC 시각
   * @return Transaction 밖의 Client 호출에 필요한 저장 결과와 이미지 참조
   * @throws BusinessException 세션·그림이 없거나 분석 불가 또는 중복인 경우
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public StartedDrawingAnalysis start(
      Long drawingSessionId,
      Long drawingAssetId,
      DrawingAnalysisType taskType,
      String requestId,
      LocalDateTime requestedAt) {
    DrawingSession session =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    if (!session.isAnalysisRequestable()) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
    }

    DrawingAsset asset =
        drawingAssetRepository
            .findById(drawingAssetId)
            .orElseThrow(
                () ->
                    new BusinessException(
                        DrawingAnalysisErrorCode.DRAWING_ANALYSIS_TARGET_NOT_FOUND));
    if (!Objects.equals(asset.getDrawingSession().getId(), session.getId())) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
    }
    DrawingAnalysisScope scope = resolveScope(asset.getAssetType(), taskType);
    if (drawingAnalysisRepository.existsActiveByAssetAndTaskType(drawingAssetId, taskType)) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_ALREADY_EXISTS);
    }

    DrawingAnalysis analysis =
        DrawingAnalysis.processing(session, asset, scope, taskType, requestId, requestedAt);
    try {
      DrawingAnalysis saved = drawingAnalysisRepository.saveAndFlush(analysis);
      return new StartedDrawingAnalysis(
          saved.getId(),
          session.getId(),
          asset.getId() == null ? drawingAssetId : asset.getId(),
          requestId,
          asset.getStorageKey(),
          asset.getMimeType(),
          requestedAt);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(
          DrawingAnalysisErrorCode.DRAWING_ANALYSIS_ALREADY_EXISTS, exception);
    }
  }

  /**
   * 재시도 원본 분석과 연결된 세션 식별자를 조회한다.
   *
   * @param analysisId 재시도할 원본 분석 식별자
   * @return 보호자 접근 검증에 사용할 원본 분석과 세션 식별자
   * @throws BusinessException 원본 분석을 찾을 수 없는 경우
   */
  @Transactional(readOnly = true, propagation = Propagation.REQUIRES_NEW)
  public RetryDrawingAnalysisSource findRetrySource(Long analysisId) {
    DrawingAnalysis source =
        drawingAnalysisRepository
            .findById(analysisId)
            .orElseThrow(
                () -> new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_FOUND));
    return new RetryDrawingAnalysisSource(source.getId(), source.getDrawingSession().getId());
  }

  /**
   * FAILED 원본을 검증하고 원본 또는 최신 그림을 사용하는 PROCESSING 재시도 행을 저장한다.
   *
   * @param analysisId 실패한 원본 분석 식별자
   * @param useLatestInputs 같은 세션·자산 유형의 최신 그림 사용 여부
   * @param requestId 새 AI 요청을 식별하는 서버 생성 UUID
   * @param requestedAt 서버가 재시도를 시작한 UTC 시각
   * @return Transaction 밖 Client 호출에 필요한 새 분석과 이미지 참조
   * @throws BusinessException 원본이 없거나 FAILED가 아니거나 활성 중복 분석이 존재하는 경우
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public StartedDrawingAnalysis startRetry(
      Long analysisId, boolean useLatestInputs, String requestId, LocalDateTime requestedAt) {
    DrawingAnalysis source =
        drawingAnalysisRepository
            .findByIdForUpdate(analysisId)
            .orElseThrow(
                () -> new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_FOUND));
    if (source.getState() != com.ssafy.b209.analysis.domain.DrawingAnalysisState.FAILED
        || source.getDrawingAsset() == null
        || source.getTaskType() == null
        || source.getScope() == null) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RETRY_NOT_ALLOWED);
    }

    DrawingSession session =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(source.getDrawingSession().getId())
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    DrawingAsset asset =
        useLatestInputs
            ? drawingAssetRepository
                .findFirstByDrawingSessionIdAndAssetTypeOrderByAssetVersionDesc(
                    session.getId(), source.getDrawingAsset().getAssetType())
                .orElse(source.getDrawingAsset())
            : source.getDrawingAsset();
    if (drawingAnalysisRepository.existsActiveByAssetAndTaskType(
        asset.getId(), source.getTaskType())) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_ALREADY_EXISTS);
    }

    DrawingAnalysis retry = DrawingAnalysis.processingRetry(source, asset, requestId, requestedAt);
    try {
      DrawingAnalysis saved = drawingAnalysisRepository.saveAndFlush(retry);
      return new StartedDrawingAnalysis(
          saved.getId(),
          session.getId(),
          asset.getId(),
          requestId,
          asset.getStorageKey(),
          asset.getMimeType(),
          requestedAt);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(
          DrawingAnalysisErrorCode.DRAWING_ANALYSIS_ALREADY_EXISTS, exception);
    }
  }

  /**
   * 유효한 Client 결과를 Detection으로 변환해 저장하고 분석을 성공 상태로 전환한다.
   *
   * @param analysisId 완료할 분석 실행 식별자
   * @param modelName 분석에 사용한 Model 이름
   * @param modelVersion 분석에 사용한 Model 버전
   * @param detections Client가 반환한 객체 탐지 목록
   * @param processedAt Client 처리가 끝난 UTC 시각
   * @return Detection과 성공 상태가 반영된 분석 실행
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public DrawingAnalysis complete(
      Long analysisId,
      String modelName,
      String modelVersion,
      List<DrawingDetectionResponse> detections,
      LocalDateTime processedAt) {
    DrawingAnalysis analysis = findForUpdate(analysisId);
    List<DrawingDetectedObject> entities = new ArrayList<>();
    for (int index = 0; index < detections.size(); index++) {
      DrawingDetectionResponse detection = detections.get(index);
      entities.add(
          DrawingDetectedObject.detected(
              detection.label(),
              detection.confidence(),
              detection.boundingBox().x(),
              detection.boundingBox().y(),
              detection.boundingBox().width(),
              detection.boundingBox().height(),
              index,
              modelVersion,
              processedAt));
    }
    analysis.succeed(modelName, modelVersion, entities, processedAt);
    drawingAnalysisRepository.flush();
    return analysis;
  }

  /**
   * Client 호출 또는 결과 저장 실패를 기존 PROCESSING 행에 기록한다.
   *
   * @param analysisId 실패 처리할 분석 실행 식별자
   * @param failureCode 원문을 포함하지 않는 실패 분류 코드
   * @param failureMessage 외부에 노출해도 되는 안전한 실패 메시지
   * @param failedAt 실패 처리가 끝난 UTC 시각
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void fail(
      Long analysisId, String failureCode, String failureMessage, LocalDateTime failedAt) {
    DrawingAnalysis analysis = findForUpdate(analysisId);
    analysis.fail(failureCode, failureMessage, failedAt);
    drawingAnalysisRepository.flush();
  }

  private DrawingAnalysis findForUpdate(Long analysisId) {
    return drawingAnalysisRepository
        .findByIdForUpdate(analysisId)
        .orElseThrow(
            () ->
                new BusinessException(
                    DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_SAVE_FAILED));
  }

  private DrawingAnalysisScope resolveScope(
      DrawingAssetType assetType, DrawingAnalysisType taskType) {
    if (taskType != DrawingAnalysisType.OBJECT_DETECTION) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
    }
    return switch (assetType) {
      case DRAFT -> DrawingAnalysisScope.INTERMEDIATE;
      case FINAL -> DrawingAnalysisScope.FINAL;
      default -> throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
    };
  }
}
