package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.dto.BoundingBoxResponse;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.analysis.dto.DrawingAnalysisModelResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
import com.ssafy.b209.analysis.dto.RetryDrawingAnalysisRequest;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClient;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClientException;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import jakarta.validation.Validator;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

/**
 * 그림 분석 시작 저장, AI Client 호출, 응답 검증과 결과 저장을 Transaction 밖에서 조율한다.
 *
 * <p>구체적인 Mock 또는 HTTP 구현을 선택하지 않고 {@link DrawingAnalysisClient} 경계에만 의존한다.
 */
@Service
public class DrawingAnalysisService {

  private static final Logger log = LoggerFactory.getLogger(DrawingAnalysisService.class);

  private final DrawingAnalysisPersistenceService persistenceService;
  private final DrawingAnalysisClient drawingAnalysisClient;
  private final Validator validator;
  private final Clock clock;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final Supplier<UUID> requestIdSupplier;

  /**
   * 그림 분석 조율에 필요한 저장 경계, Client, 계약 검증기와 UTC 시계를 주입받는다.
   *
   * @param persistenceService 독립 Transaction으로 분석 상태를 저장하는 서비스
   * @param drawingAnalysisClient 활성화된 그림 분석 Client
   * @param validator AI 응답 계약을 검증하는 Bean Validator
   * @param clock 요청 및 실패 시각을 생성하는 UTC 시계
   * @param currentUserResolver Access Token에서 현재 사용자 ID를 제공하는 Resolver
   * @param accessValidator 보호자와 그림 활동의 연결 관계를 검증하는 Validator
   */
  @Autowired
  public DrawingAnalysisService(
      DrawingAnalysisPersistenceService persistenceService,
      DrawingAnalysisClient drawingAnalysisClient,
      Validator validator,
      Clock clock,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this(
        persistenceService,
        drawingAnalysisClient,
        validator,
        clock,
        currentUserResolver,
        accessValidator,
        UUID::randomUUID);
  }

  DrawingAnalysisService(
      DrawingAnalysisPersistenceService persistenceService,
      DrawingAnalysisClient drawingAnalysisClient,
      Validator validator,
      Clock clock,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      Supplier<UUID> requestIdSupplier) {
    this.persistenceService = Objects.requireNonNull(persistenceService);
    this.drawingAnalysisClient = Objects.requireNonNull(drawingAnalysisClient);
    this.validator = Objects.requireNonNull(validator);
    this.clock = Objects.requireNonNull(clock);
    this.currentUserResolver = Objects.requireNonNull(currentUserResolver);
    this.accessValidator = Objects.requireNonNull(accessValidator);
    this.requestIdSupplier = Objects.requireNonNull(requestIdSupplier);
  }

  /**
   * DRAFT 또는 FINAL 그림 객체 탐지를 동기식으로 실행하고 저장된 성공 결과를 반환한다.
   *
   * @param drawingSessionId 분석 대상 그림 활동 세션 식별자
   * @param request 그림 파일 식별자와 AI 분석 작업 유형
   * @return 내부 저장소 정보를 제외한 저장 완료 결과
   * @throws BusinessException 대상·상태·중복 검증, Client 호출 또는 결과 저장에 실패한 경우
   */
  public CreateDrawingAnalysisResponse requestAnalysis(
      Long drawingSessionId, CreateDrawingAnalysisRequest request) {
    return requestAnalysis(drawingSessionId, request, requestIdSupplier.get().toString(), false);
  }

  /**
   * 호출자가 지정한 요청 식별자로 FINAL 그림 객체 탐지를 동기식으로 실행한다.
   *
   * <p>그림 단계 완료 API의 {@code Idempotency-Key}와 분석 실행을 연결할 때 사용한다. 접근 권한과 분석 대상 검증은 일반 분석 요청과 동일하게
   * 적용한다.
   *
   * @param drawingSessionId 분석 대상 그림 활동 세션 식별자
   * @param request 그림 파일 식별자와 AI 분석 작업 유형
   * @param requestId 분석 실행을 식별하는 멱등 요청 값
   * @return 내부 저장소 정보를 제외한 저장 완료 결과
   * @throws BusinessException 대상·상태·중복 검증, Client 호출 또는 결과 저장에 실패한 경우
   */
  public CreateDrawingAnalysisResponse requestAnalysis(
      Long drawingSessionId, CreateDrawingAnalysisRequest request, String requestId) {
    return requestAnalysis(drawingSessionId, request, requestId, true);
  }

  private CreateDrawingAnalysisResponse requestAnalysis(
      Long drawingSessionId,
      CreateDrawingAnalysisRequest request,
      String requestId,
      boolean drawingStageCompletion) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    Instant requestedInstant = clock.instant();
    LocalDateTime requestedAt = LocalDateTime.ofInstant(requestedInstant, ZoneOffset.UTC);
    StartedDrawingAnalysis started =
        drawingStageCompletion
            ? persistenceService.startForDrawingCompletion(
                drawingSessionId,
                request.drawingAssetId(),
                request.analysisType(),
                requestId,
                requestedAt)
            : persistenceService.start(
                drawingSessionId,
                request.drawingAssetId(),
                request.analysisType(),
                requestId,
                requestedAt);

    return executeAnalysis(started, request.analysisType(), requestedInstant);
  }

  /**
   * FAILED 분석을 원본으로 연결한 새 분석 실행을 요청한다.
   *
   * @param analysisId 실패한 원본 분석 식별자
   * @param request 재시도 사유와 입력 선택 정책
   * @return 새로 생성되고 저장된 분석 결과
   * @throws BusinessException 원본 접근·상태 검증, Client 호출 또는 결과 저장에 실패한 경우
   */
  public CreateDrawingAnalysisResponse retryAnalysis(
      Long analysisId, RetryDrawingAnalysisRequest request) {
    Long guardianUserId = currentUserResolver.requireUserId();
    RetryDrawingAnalysisSource source = persistenceService.findRetrySource(analysisId);
    accessValidator.requireDrawingSessionAccess(guardianUserId, source.drawingSessionId());
    String requestId = requestIdSupplier.get().toString();
    Instant requestedInstant = clock.instant();
    StartedDrawingAnalysis started =
        persistenceService.startRetry(
            analysisId,
            request.useLatestInputs(),
            requestId,
            LocalDateTime.ofInstant(requestedInstant, ZoneOffset.UTC));
    return executeAnalysis(started, DrawingAnalysisType.OBJECT_DETECTION, requestedInstant);
  }

  private CreateDrawingAnalysisResponse executeAnalysis(
      StartedDrawingAnalysis started, DrawingAnalysisType taskType, Instant requestedInstant) {
    String requestId = started.requestId();
    DrawingAnalysisClientCommand clientRequest =
        new DrawingAnalysisClientCommand(
            requestId,
            started.analysisId(),
            started.drawingSessionId(),
            started.drawingAssetId(),
            started.analysisScope(),
            started.activityType(),
            started.drawingSubject(),
            started.storageKey(),
            started.contentType(),
            started.widthPx(),
            started.heightPx(),
            started.checksumSha256());
    AiDrawingAnalysisResponse clientResponse;
    try {
      clientResponse = drawingAnalysisClient.analyze(clientRequest);
    } catch (DrawingAnalysisClientException exception) {
      DrawingAnalysisErrorCode errorCode = errorCodeFor(exception);
      markFailed(started.analysisId(), exception.getType().name(), errorCode);
      throw new BusinessException(errorCode, exception);
    } catch (RuntimeException exception) {
      DrawingAnalysisErrorCode errorCode = DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED;
      markFailed(started.analysisId(), "UNEXPECTED_CLIENT_ERROR", errorCode);
      throw new BusinessException(errorCode, exception);
    }

    DrawingAnalysisErrorCode validationError =
        validateResponse(started.analysisId(), clientResponse);
    if (validationError != null) {
      markFailed(started.analysisId(), failureCode(validationError), validationError);
      throw new BusinessException(validationError);
    }

    Instant processedInstant = clock.instant();
    AiDrawingAnalysisResponse.ModelRef objectDetection =
        clientResponse.modelInfo().objectDetection();
    try {
      persistenceService.completeCanonical(
          started.analysisId(),
          clientResponse,
          LocalDateTime.ofInstant(processedInstant, ZoneOffset.UTC));
    } catch (RuntimeException exception) {
      markFailed(
          started.analysisId(),
          "RESULT_SAVE_FAILED",
          DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_SAVE_FAILED);
      throw new BusinessException(
          DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_SAVE_FAILED, exception);
    }

    DrawingAnalysisModelResponse publicModel =
        new DrawingAnalysisModelResponse(objectDetection.name(), objectDetection.version());
    List<DrawingDetectionResponse> publicDetections =
        clientResponse.detectedObjects().stream()
            .map(
                detection ->
                    new DrawingDetectionResponse(
                        detection.objectCode(),
                        detection.confidence(),
                        new BoundingBoxResponse(
                            detection.boundingBox().x(),
                            detection.boundingBox().y(),
                            detection.boundingBox().width(),
                            detection.boundingBox().height())))
            .toList();
    return new CreateDrawingAnalysisResponse(
        started.analysisId(),
        started.drawingSessionId(),
        started.drawingAssetId(),
        requestId,
        taskType,
        DrawingAnalysisStatus.SUCCEEDED,
        publicModel,
        publicDetections,
        requestedInstant,
        processedInstant);
  }

  private DrawingAnalysisErrorCode validateResponse(
      Long analysisId, AiDrawingAnalysisResponse response) {
    if (response == null
        || !analysisId.equals(response.analysisId())
        || !validator.validate(response).isEmpty()) {
      return DrawingAnalysisErrorCode.DRAWING_ANALYSIS_INVALID_RESPONSE;
    }
    if (response.status() == AiDrawingAnalysisResponse.AnalysisStatus.FAILED) {
      return DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED;
    }
    if (response.modelInfo().objectDetection() == null) {
      return DrawingAnalysisErrorCode.DRAWING_ANALYSIS_INVALID_RESPONSE;
    }
    return null;
  }

  private DrawingAnalysisErrorCode errorCodeFor(DrawingAnalysisClientException exception) {
    return exception.getType() == DrawingAnalysisClientException.Type.INVALID_RESPONSE
        ? DrawingAnalysisErrorCode.DRAWING_ANALYSIS_INVALID_RESPONSE
        : DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED;
  }

  private String failureCode(DrawingAnalysisErrorCode errorCode) {
    return errorCode == DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED
        ? "REQUEST_FAILED"
        : "INVALID_RESPONSE";
  }

  private void markFailed(Long analysisId, String failureCode, DrawingAnalysisErrorCode errorCode) {
    try {
      persistenceService.fail(
          analysisId,
          failureCode,
          errorCode.getMessage(),
          LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
    } catch (RuntimeException failureSaveException) {
      log.error(
          "분석 실패 상태 저장에 실패했습니다. analysisId={}, exceptionType={}",
          analysisId,
          failureSaveException.getClass().getSimpleName());
    }
  }
}
