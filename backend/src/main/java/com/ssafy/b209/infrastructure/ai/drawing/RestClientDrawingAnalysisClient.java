package com.ssafy.b209.infrastructure.ai.drawing;

import com.ssafy.b209.analysis.dto.DrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisResponse;
import jakarta.validation.Validator;
import java.net.SocketTimeoutException;
import java.net.http.HttpTimeoutException;
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

  private final RestClient restClient;
  private final String endpointPath;
  private final Validator validator;

  RestClientDrawingAnalysisClient(RestClient restClient, String endpointPath, Validator validator) {
    this.restClient = restClient;
    this.endpointPath = endpointPath;
    this.validator = validator;
  }

  /**
   * 설정된 내부 Endpoint에 그림 분석 요청을 전송하고 유효한 응답을 반환한다.
   *
   * @param request 144번 이슈에서 확정한 그림 분석 요청
   * @return Bean Validation을 통과한 그림 분석 응답
   * @throws DrawingAnalysisClientException 요청 또는 응답 계약이 유효하지 않은 경우
   */
  @Override
  public DrawingAnalysisResponse analyze(DrawingAnalysisRequest request) {
    if (request == null || !validator.validate(request).isEmpty()) {
      throw new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    }

    DrawingAnalysisResponse response;
    try {
      response =
          restClient
              .post()
              .uri(endpointPath)
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
              .body(DrawingAnalysisResponse.class);
    } catch (DrawingAnalysisClientException exception) {
      throw exception;
    } catch (ResourceAccessException exception) {
      throw new DrawingAnalysisClientException(
          hasTimeoutCause(exception)
              ? DrawingAnalysisClientException.Type.TIMEOUT
              : DrawingAnalysisClientException.Type.REQUEST_FAILED,
          exception);
    } catch (RestClientException exception) {
      throw new DrawingAnalysisClientException(
          DrawingAnalysisClientException.Type.INVALID_RESPONSE, exception);
    }

    if (response == null
        || !request.requestId().equals(response.requestId())
        || !validator.validate(response).isEmpty()) {
      throw new DrawingAnalysisClientException(
          DrawingAnalysisClientException.Type.INVALID_RESPONSE);
    }
    return response;
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
