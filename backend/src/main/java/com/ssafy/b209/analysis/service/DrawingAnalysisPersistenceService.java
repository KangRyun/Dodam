package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.domain.DrawingAnalysisTriggerReason;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.repository.AnalysisResultJdbcRepository;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
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

  private static final int MAX_RETRY_ATTEMPTS = 3;

  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingAssetRepository drawingAssetRepository;
  private final DrawingAnalysisRepository drawingAnalysisRepository;
  private final AnalysisResultJdbcRepository analysisResultJdbcRepository;
  private final DrawingAnalysisActivityContextResolver activityContextResolver;
  private final ConversationSessionRepository conversationSessionRepository;

  /**
   * 분석 저장에 필요한 Repository를 주입받는다.
   *
   * @param drawingSessionRepository 분석 가능 세션 조회와 잠금 저장소
   * @param drawingAssetRepository 분석 대상 그림 파일 저장소
   * @param drawingAnalysisRepository 분석 실행 저장소
   * @param analysisResultJdbcRepository 정규화된 종합 분석 보조 결과 저장소
   * @param activityContextResolver 저장된 세션과 HTP 단계에서 AI 활동 맥락을 확정하는 Resolver
   * @param conversationSessionRepository 그림 작성 중 종료된 대화 상태 조회 저장소
   */
  public DrawingAnalysisPersistenceService(
      DrawingSessionRepository drawingSessionRepository,
      DrawingAssetRepository drawingAssetRepository,
      DrawingAnalysisRepository drawingAnalysisRepository,
      AnalysisResultJdbcRepository analysisResultJdbcRepository,
      DrawingAnalysisActivityContextResolver activityContextResolver,
      ConversationSessionRepository conversationSessionRepository) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingAssetRepository = drawingAssetRepository;
    this.drawingAnalysisRepository = drawingAnalysisRepository;
    this.analysisResultJdbcRepository = analysisResultJdbcRepository;
    this.activityContextResolver = activityContextResolver;
    this.conversationSessionRepository = conversationSessionRepository;
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
    return start(
        drawingSessionId,
        drawingAssetId,
        taskType,
        requestId,
        DrawingAnalysisTriggerReason.USER_REQUEST,
        requestedAt,
        false);
  }

  /**
   * 공개 API에서 확정한 실행 사유로 처리 중인 분석을 저장한다.
   *
   * @param drawingSessionId 분석 대상 그림 세션 식별자
   * @param drawingAssetId 분석 대상 그림 파일 식별자
   * @param taskType 수행할 분석 유형
   * @param requestId 요청 추적 식별자
   * @param triggerReason 분석을 시작한 실제 계기
   * @param requestedAt 서버가 요청을 시작한 UTC 시각
   * @return AI Client 호출에 필요한 저장 결과
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public StartedDrawingAnalysis start(
      Long drawingSessionId,
      Long drawingAssetId,
      DrawingAnalysisType taskType,
      String requestId,
      DrawingAnalysisTriggerReason triggerReason,
      LocalDateTime requestedAt) {
    return start(
        drawingSessionId, drawingAssetId, taskType, requestId, triggerReason, requestedAt, false);
  }

  /**
   * 그림 단계 완료 요청의 PROCESSING 분석을 만들고 FINAL 분석이면 세션을 ANALYZING으로 전환한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param drawingAssetId 분석 대상 FINAL 그림 파일 식별자
   * @param taskType 수행할 AI 분석 작업 유형
   * @param requestId 완료 요청의 {@code Idempotency-Key}
   * @param requestedAt 서버가 분석 요청을 시작한 UTC 시각
   * @return Transaction 밖의 Client 호출에 필요한 저장 결과와 이미지 참조
   * @throws BusinessException 세션·그림이 없거나 분석 불가 또는 중복인 경우
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public StartedDrawingAnalysis startForDrawingCompletion(
      Long drawingSessionId,
      Long drawingAssetId,
      DrawingAnalysisType taskType,
      String requestId,
      LocalDateTime requestedAt) {
    return start(
        drawingSessionId,
        drawingAssetId,
        taskType,
        requestId,
        DrawingAnalysisTriggerReason.USER_REQUEST,
        requestedAt,
        true);
  }

  /**
   * 그림 단계 완료 요청의 실행 사유와 함께 FINAL 분석을 저장한다.
   *
   * @param drawingSessionId 분석 대상 그림 세션 식별자
   * @param drawingAssetId 분석 대상 FINAL 파일 식별자
   * @param taskType 수행할 분석 유형
   * @param requestId 완료 요청의 멱등 식별자
   * @param triggerReason 분석을 시작한 실제 계기
   * @param requestedAt 서버가 요청을 시작한 UTC 시각
   * @return AI Client 호출에 필요한 저장 결과
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public StartedDrawingAnalysis startForDrawingCompletion(
      Long drawingSessionId,
      Long drawingAssetId,
      DrawingAnalysisType taskType,
      String requestId,
      DrawingAnalysisTriggerReason triggerReason,
      LocalDateTime requestedAt) {
    return start(
        drawingSessionId, drawingAssetId, taskType, requestId, triggerReason, requestedAt, true);
  }

  private StartedDrawingAnalysis start(
      Long drawingSessionId,
      Long drawingAssetId,
      DrawingAnalysisType taskType,
      String requestId,
      DrawingAnalysisTriggerReason triggerReason,
      LocalDateTime requestedAt,
      boolean drawingStageCompletion) {
    DrawingSession session =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    if (!session.isAnalysisRequestable()) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
    }
    DrawingAnalysisActivityContext activityContext = activityContextResolver.resolve(session);

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
    DrawingAnalysisScope scope =
        resolveScope(
            asset.getAssetType(), taskType, drawingStageCompletion, session.getInputMethod());
    if (drawingAnalysisRepository.existsActiveByAssetAndTaskType(drawingAssetId, taskType)) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_ALREADY_EXISTS);
    }

    DrawingAnalysis analysis =
        DrawingAnalysis.processing(
            session, asset, scope, taskType, requestId, triggerReason, requestedAt);
    try {
      DrawingAnalysis saved = drawingAnalysisRepository.saveAndFlush(analysis);
      if (drawingStageCompletion && scope == DrawingAnalysisScope.FINAL) {
        session.startDrawingAnalysis();
      }
      return new StartedDrawingAnalysis(
          saved.getId(),
          session.getId(),
          asset.getId() == null ? drawingAssetId : asset.getId(),
          requestId,
          scope,
          activityContext.activityType(),
          activityContext.drawingSubject(),
          saved.getTriggerReason(),
          asset.getStorageKey(),
          asset.getMimeType(),
          asset.getWidthPx(),
          asset.getHeightPx(),
          asset.getChecksumSha256(),
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
   * 멱등 요청 식별자로 저장된 분석과 현재 세션 상태를 조회한다.
   *
   * @param requestId 분석 생성에 사용한 요청 식별자
   * @return 저장된 분석 요약, 사용되지 않은 식별자면 빈 값
   */
  @Transactional(readOnly = true, propagation = Propagation.REQUIRES_NEW)
  public Optional<DrawingAnalysisRequestSummary> findByRequestId(String requestId) {
    return drawingAnalysisRepository
        .findByRequestId(requestId)
        .map(
            analysis ->
                new DrawingAnalysisRequestSummary(
                    analysis.getId(),
                    analysis.getDrawingSession().getId(),
                    analysis.getDrawingAsset().getId(),
                    analysis.getTaskType(),
                    analysis.getState(),
                    analysis.getDrawingSession().getSessionStatus(),
                    analysis.getDrawingSession().getCurrentStage(),
                    analysis.getRetryOfAnalysis() == null
                        ? null
                        : analysis.getRetryOfAnalysis().getId()));
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
    validateRetryPolicy(source);

    DrawingSession session =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(source.getDrawingSession().getId())
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    DrawingAnalysisActivityContext activityContext = activityContextResolver.resolve(session);
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
          source.getScope(),
          activityContext.activityType(),
          activityContext.drawingSubject(),
          saved.getTriggerReason(),
          asset.getStorageKey(),
          asset.getMimeType(),
          asset.getWidthPx(),
          asset.getHeightPx(),
          asset.getChecksumSha256(),
          requestedAt);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(
          DrawingAnalysisErrorCode.DRAWING_ANALYSIS_ALREADY_EXISTS, exception);
    }
  }

  private void validateRetryPolicy(DrawingAnalysis source) {
    int retryAttempts = 0;
    DrawingAnalysis current = source;
    while (current.getRetryOfAnalysis() != null) {
      retryAttempts++;
      if (retryAttempts >= MAX_RETRY_ATTEMPTS) {
        throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RETRY_LIMIT_EXCEEDED);
      }
      current = current.getRetryOfAnalysis();
    }
    if (drawingAnalysisRepository.existsByRetryOfAnalysisId(source.getId())) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RETRY_NOT_ALLOWED);
    }
  }

  /**
   * 정본 AI 응답의 객체명·정규화 좌표·면적 비율을 보존하고 전체 또는 부분 성공 상태로 전환한다.
   *
   * @param analysisId 완료할 분석 실행 식별자
   * @param response 검증된 정본 종합 분석 응답
   * @param processedAt Spring Boot가 응답 처리를 완료한 UTC 시각
   * @return 탐지 결과와 완료 상태가 반영된 분석 실행
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public DrawingAnalysis completeCanonical(
      Long analysisId, AiDrawingAnalysisResponse response, LocalDateTime processedAt) {
    DrawingAnalysis analysis = findForUpdate(analysisId);
    AiDrawingAnalysisResponse.ModelRef model = response.modelInfo().objectDetection();
    List<DrawingDetectedObject> entities = new ArrayList<>();
    for (AiDrawingAnalysisResponse.DetectedObject detection : response.detectedObjects()) {
      AiDrawingAnalysisResponse.BoundingBox box = detection.boundingBox();
      entities.add(
          DrawingDetectedObject.detected(
              detection.objectCode(),
              detection.objectName(),
              detection.confidence(),
              box.x(),
              box.y(),
              box.width(),
              box.height(),
              detection.areaRatio(),
              detection.detectionOrder(),
              model.version(),
              processedAt));
    }
    DrawingAnalysisState completedState =
        response.status() == AiDrawingAnalysisResponse.AnalysisStatus.PARTIAL_SUCCESS
            ? DrawingAnalysisState.PARTIAL_SUCCESS
            : DrawingAnalysisState.SUCCESS;
    analysis.complete(completedState, model.name(), model.version(), entities, processedAt);
    finishFinalDrawingAnalysis(analysis);
    analysisResultJdbcRepository.replace(analysisId, response, processedAt);
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
    finishFinalDrawingAnalysis(analysis);
    drawingAnalysisRepository.flush();
  }

  private void finishFinalDrawingAnalysis(DrawingAnalysis analysis) {
    if (analysis.getScope() == DrawingAnalysisScope.FINAL
        && analysis.getDrawingSession().getCurrentStage()
            == com.ssafy.b209.drawing.domain.DrawingStage.ANALYZING) {
      boolean conversationCompleted =
          conversationSessionRepository
              .findByDrawingSessionId(analysis.getDrawingSession().getId())
              .map(ConversationSession::isCompleted)
              .orElse(false);
      analysis.getDrawingSession().finishDrawingAnalysis(conversationCompleted);
    }
  }

  private DrawingAnalysis findForUpdate(Long analysisId) {
    return drawingAnalysisRepository
        .findByIdForUpdate(analysisId)
        .orElseThrow(
            () ->
                new BusinessException(
                    DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_SAVE_FAILED));
  }

  /**
   * 분석 대상 파일 유형으로 저장할 분석 범위를 확정한다.
   *
   * <p>공개 분석 요청은 {@code DRAFT}와 {@code FINAL}만 허용한다. 사진 업로드로 시작한 그림은 최종 그림을 다시 저장하지 않고 업로드 원본이
   * 결과물이므로, 그림 단계 완료 경로에서만 {@code UPLOADED} 원본을 {@code FINAL} 범위 분석의 대상으로 받아들인다.
   */
  private DrawingAnalysisScope resolveScope(
      DrawingAssetType assetType,
      DrawingAnalysisType taskType,
      boolean drawingStageCompletion,
      DrawingInputMethod inputMethod) {
    if (taskType != DrawingAnalysisType.OBJECT_DETECTION) {
      throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
    }
    return switch (assetType) {
      case DRAFT -> DrawingAnalysisScope.INTERMEDIATE;
      case FINAL -> DrawingAnalysisScope.FINAL;
      case UPLOADED -> {
        if (!drawingStageCompletion || inputMethod != DrawingInputMethod.UPLOAD) {
          throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
        }
        yield DrawingAnalysisScope.FINAL;
      }
      default -> throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
    };
  }
}
