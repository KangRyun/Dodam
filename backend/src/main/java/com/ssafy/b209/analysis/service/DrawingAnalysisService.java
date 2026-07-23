package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.CreateDrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingImageReference;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClient;
import com.ssafy.b209.infrastructure.ai.drawing.DrawingAnalysisClientException;
import jakarta.validation.Validator;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
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
   * 최종 그림 분석을 동기식으로 실행하고 저장된 성공 결과를 반환한다.
   *
   * @param drawingSessionId 분석 대상 그림 활동 세션 식별자
   * @param request 그림 파일 식별자와 AI 분석 작업 유형
   * @return 내부 저장소 정보를 제외한 저장 완료 결과
   * @throws BusinessException 대상·상태·중복 검증, Client 호출 또는 결과 저장에 실패한 경우
   */
  public CreateDrawingAnalysisResponse requestAnalysis(
      Long drawingSessionId, CreateDrawingAnalysisRequest request) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    String requestId = requestIdSupplier.get().toString();
    Instant requestedInstant = clock.instant();
    LocalDateTime requestedAt = LocalDateTime.ofInstant(requestedInstant, ZoneOffset.UTC);
    StartedDrawingAnalysis started =
        persistenceService.start(
            drawingSessionId,
            request.drawingAssetId(),
            request.analysisType(),
            requestId,
            requestedAt);

    DrawingAnalysisRequest clientRequest =
        new DrawingAnalysisRequest(
            requestId,
            started.drawingSessionId(),
            started.drawingAssetId(),
            new DrawingImageReference(started.storageKey(), started.contentType()),
            request.analysisType());
    DrawingAnalysisResponse clientResponse;
    try {
      clientResponse = drawingAnalysisClient.analyze(clientRequest);
    } catch (DrawingAnalysisClientException exception) {
      DrawingAnalysisErrorCode errorCode = errorCodeFor(exception);
      markFailed(started.analysisId(), exception.getType().name(), errorCode);
      throw new BusinessException(errorCode, exception);
    }

    DrawingAnalysisErrorCode validationError = validateResponse(requestId, clientResponse);
    if (validationError != null) {
      markFailed(started.analysisId(), failureCode(validationError), validationError);
      throw new BusinessException(validationError);
    }

    try {
      persistenceService.complete(
          started.analysisId(),
          clientResponse.model().name(),
          clientResponse.model().version(),
          clientResponse.detections(),
          LocalDateTime.ofInstant(clientResponse.processedAt(), ZoneOffset.UTC));
    } catch (RuntimeException exception) {
      markFailed(
          started.analysisId(),
          "RESULT_SAVE_FAILED",
          DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_SAVE_FAILED);
      throw new BusinessException(
          DrawingAnalysisErrorCode.DRAWING_ANALYSIS_RESULT_SAVE_FAILED, exception);
    }

    return new CreateDrawingAnalysisResponse(
        started.analysisId(),
        started.drawingSessionId(),
        started.drawingAssetId(),
        requestId,
        request.analysisType(),
        DrawingAnalysisStatus.SUCCEEDED,
        clientResponse.model(),
        clientResponse.detections(),
        requestedInstant,
        clientResponse.processedAt());
  }

  private DrawingAnalysisErrorCode validateResponse(
      String requestId, DrawingAnalysisResponse response) {
    if (response == null
        || !requestId.equals(response.requestId())
        || !validator.validate(response).isEmpty()) {
      return DrawingAnalysisErrorCode.DRAWING_ANALYSIS_INVALID_RESPONSE;
    }
    if (response.status() == DrawingAnalysisStatus.FAILED) {
      return DrawingAnalysisErrorCode.DRAWING_ANALYSIS_REQUEST_FAILED;
    }
    if (response.status() != DrawingAnalysisStatus.SUCCEEDED) {
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
