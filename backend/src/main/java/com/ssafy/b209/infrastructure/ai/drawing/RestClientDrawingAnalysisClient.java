package com.ssafy.b209.infrastructure.ai.drawing;

import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisRequest;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validator;
import java.net.SocketTimeoutException;
import java.net.URI;
import java.net.http.HttpTimeoutException;
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
  private final Validator validator;

  RestClientDrawingAnalysisClient(
      RestClient restClient,
      String endpointPath,
      String internalToken,
      DrawingAnalysisImageUrlProvider imageUrlProvider,
      Validator validator) {
    this.restClient = restClient;
    this.endpointPath = endpointPath;
    if (internalToken == null || internalToken.isBlank()) {
      throw new IllegalArgumentException("internalToken must not be blank");
    }
    this.internalToken = internalToken;
    this.imageUrlProvider = imageUrlProvider;
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
        AiDrawingAnalysisRequest.minimum(
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
                command.checksumSha256()));
    if (!validator.validate(request).isEmpty()) {
      throw new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    }
    return request;
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
