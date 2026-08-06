package com.ssafy.b209.infrastructure.ai.drawing;

import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.drawing.service.StrokeBehaviorSummary;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisRequest;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validator;
import java.net.SocketTimeoutException;
import java.net.URI;
import java.net.http.HttpTimeoutException;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.NestedExceptionUtils;
import org.springframework.http.MediaType;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * Spring RestClient로 그림 분석 JSON 계약을 호출하는 HTTP 어댑터다.
 *
 * <p>Entity나 HTTP 응답 객체를 상위 계층에 노출하지 않으며 요청 전후에 144번 계약의 Bean Validation을 적용한다.
 */
public final class RestClientDrawingAnalysisClient implements DrawingAnalysisClient {

  private static final Logger log = LoggerFactory.getLogger(RestClientDrawingAnalysisClient.class);

  private final RestClient restClient;
  private final String endpointPath;
  private final String internalToken;
  private final DrawingAnalysisImageUrlProvider imageUrlProvider;
  private final DrawingBehaviorSummaryProvider behaviorSummaryProvider;
  private final Validator validator;

  RestClientDrawingAnalysisClient(
      RestClient restClient,
      String endpointPath,
      String internalToken,
      DrawingAnalysisImageUrlProvider imageUrlProvider,
      DrawingBehaviorSummaryProvider behaviorSummaryProvider,
      Validator validator) {
    this.restClient = restClient;
    this.endpointPath = endpointPath;
    if (internalToken == null || internalToken.isBlank()) {
      throw new IllegalArgumentException("internalToken must not be blank");
    }
    this.internalToken = internalToken;
    this.imageUrlProvider = imageUrlProvider;
    this.behaviorSummaryProvider = behaviorSummaryProvider;
    this.validator = validator;
  }

  /**
   * 정본 내부 Endpoint에 인증된 종합 분석 요청을 전송한다.
   *
   * @param command 저장된 분석과 이미지 Metadata를 포함한 호출 명령
   * @return 검증된 §19.4 종합 분석 응답
   * @throws DrawingAnalysisClientException 요청 생성, 통신 또는 응답 검증에 실패한 경우
   */
  @Override
  public AiDrawingAnalysisResponse analyze(DrawingAnalysisClientCommand command) {
    if (command == null || !validator.validate(command).isEmpty()) {
      throw new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    }

    AiDrawingAnalysisRequest request = toRequest(command);
    AiDrawingAnalysisResponse response;
    try {
      response =
          restClient
              .post()
              .uri(endpointPath)
              .header("X-Internal-Token", internalToken)
              .header("X-Request-Id", command.requestId())
              .contentType(MediaType.APPLICATION_JSON)
              .body(request)
              .retrieve()
              .onStatus(
                  status -> !status.is2xxSuccessful(),
                  (clientRequest, clientResponse) -> {
                    throw new DrawingAnalysisClientException(
                        clientResponse.getStatusCode().is5xxServerError()
                            ? DrawingAnalysisClientException.Type.SERVER_ERROR
                            : DrawingAnalysisClientException.Type.REQUEST_FAILED);
                  })
              .body(AiDrawingAnalysisResponse.class);
    } catch (DrawingAnalysisClientException exception) {
      throw exception;
    } catch (ResourceAccessException exception) {
      throw new DrawingAnalysisClientException(
          hasTimeoutCause(exception)
              ? DrawingAnalysisClientException.Type.TIMEOUT
              : DrawingAnalysisClientException.Type.REQUEST_FAILED,
          exception);
    } catch (RestClientException exception) {
      log.warn(
          "[735] AI 응답 역직렬화 실패: {}",
          NestedExceptionUtils.getMostSpecificCause(exception).getMessage());
      throw new DrawingAnalysisClientException(
          DrawingAnalysisClientException.Type.INVALID_RESPONSE, exception);
    }

    Set<ConstraintViolation<AiDrawingAnalysisResponse>> violations =
        response == null ? Set.of() : validator.validate(response);
    boolean idMatch =
        response != null && Objects.equals(command.analysisId(), response.analysisId());
    if (response == null || !idMatch || !violations.isEmpty()) {
      log.warn(
          "[735] AI 응답 검증 실패: reqId={}, respId={}, idMatch={}, status={}, violations={}",
          command.analysisId(),
          response == null ? null : response.analysisId(),
          idMatch,
          response == null ? null : response.status(),
          violations.stream()
              .map(violation -> violation.getPropertyPath() + ": " + violation.getMessage())
              .toList());
      throw new DrawingAnalysisClientException(
          DrawingAnalysisClientException.Type.INVALID_RESPONSE);
    }
    return response;
  }

  private AiDrawingAnalysisRequest toRequest(DrawingAnalysisClientCommand command) {
    URI signedUrl = imageUrlProvider.createReadUrl(command.storageKey());
    if (signedUrl == null || !signedUrl.isAbsolute()) {
      throw new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    }
    AiDrawingAnalysisRequest.AnalysisType analysisType =
        command.analysisScope() == com.ssafy.b209.analysis.domain.DrawingAnalysisScope.INTERMEDIATE
            ? AiDrawingAnalysisRequest.AnalysisType.INTERMEDIATE
            : AiDrawingAnalysisRequest.AnalysisType.FINAL;
    AiDrawingAnalysisRequest request =
        AiDrawingAnalysisRequest.withBehavior(
            command.analysisId(),
            command.drawingSessionId(),
            command.activityType(),
            command.drawingSubject(),
            analysisType,
            AiDrawingAnalysisRequest.TriggerReason.valueOf(command.triggerReason().name()),
            new AiDrawingAnalysisRequest.DrawingInput(
                command.drawingAssetId(),
                signedUrl.toString(),
                command.mimeType(),
                command.width(),
                command.height(),
                command.inputMethod(),
                command.checksumSha256()),
            behaviorInput(command, analysisType));
    if (!validator.validate(request).isEmpty()) {
      throw new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    }
    return request;
  }

  /**
   * 최종 분석에만 저장된 그리기 과정 요약을 붙인다.
   *
   * <p>중간 분석은 자동 저장 debounce마다 실행되는데 집계는 그 시점까지의 배치를 매번 전부 읽는다. 한 세션에서 중간 분석이 반복될수록 읽는 양이 누적으로
   * 커지므로, 단계별 성능 실측(S15P11B209-609)에서 비용을 확인하기 전까지는 완료 조건이 요구하는 최종 분석에만 싣는다. 중간 분석은 지금처럼 AI가 {@code
   * BEHAVIOR_SUMMARY_ABSENT}로 표시한다.
   *
   * <p>저장소 조회가 실패해도 분석 자체를 실패시키지 않는다. 행동 요약은 그림 분석의 부가 입력이고, 없으면 AI가 사실대로 미사용 입력으로 남긴다.
   */
  private AiDrawingAnalysisRequest.BehaviorInput behaviorInput(
      DrawingAnalysisClientCommand command, AiDrawingAnalysisRequest.AnalysisType analysisType) {
    if (analysisType != AiDrawingAnalysisRequest.AnalysisType.FINAL) {
      return null;
    }
    try {
      return behaviorSummaryProvider
          .findByDrawingSession(command.drawingSessionId())
          .map(RestClientDrawingAnalysisClient::toBehaviorInput)
          .orElse(null);
    } catch (RuntimeException exception) {
      log.warn(
          "[772] 행동 요약 집계 실패로 behavior 없이 분석을 요청한다: analysisId={}, cause={}",
          command.analysisId(),
          exception.getClass().getSimpleName());
      return null;
    }
  }

  /**
   * 집계 결과를 §19.3 계약 형태로 옮긴다.
   *
   * <p>{@link StrokeBehaviorSummary#truncated()}는 계약에 자리가 없어 전달하지 않는다. 부분 집계라는 사실은 집계 시점의 경고 로그로만
   * 남는다 — 계약에 필드를 추가하려면 AI와 합의해야 한다.
   */
  private static AiDrawingAnalysisRequest.BehaviorInput toBehaviorInput(
      StrokeBehaviorSummary summary) {
    return new AiDrawingAnalysisRequest.BehaviorInput(
        // 획 원본 해석(strokeBatchUrls)은 아직 AI가 구현하지 않았다. 빈 목록으로 보내야 AI가
        //   "받았지만 쓰지 않았다"는 STROKE_BATCH_NOT_ANALYZED 경고를 남기지 않는다.
        List.of(),
        new AiDrawingAnalysisRequest.BehaviorSummary(
            summary.drawingDurationMs(),
            summary.activeDrawingMs(),
            summary.strokeCount(),
            summary.pauseCount(),
            summary.undoCount(),
            summary.eraseCount(),
            summary.toolChangeCount(),
            summary.colorChangeCount(),
            // 집계하지 못한 색 집합(null)은 가짓수도 알 수 없다 — 0으로 세지 않는다.
            summary.colorsUsed() == null ? null : summary.colorsUsed().size(),
            summary.pressureAvailable()));
  }

  private boolean hasTimeoutCause(Throwable throwable) {
    Throwable current = throwable;
    while (current != null) {
      if (current instanceof SocketTimeoutException || current instanceof HttpTimeoutException) {
        return true;
      }
      current = current.getCause();
    }
    return false;
  }
}
