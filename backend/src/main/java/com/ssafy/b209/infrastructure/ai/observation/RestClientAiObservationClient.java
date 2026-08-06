package com.ssafy.b209.infrastructure.ai.observation;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.report.dto.ObservationGeneration;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import jakarta.validation.Validator;
import java.net.SocketTimeoutException;
import java.net.http.HttpTimeoutException;
import java.util.Objects;
import org.springframework.http.MediaType;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * Spring RestClient로 관찰 리포트 생성 JSON 계약을 호출하는 HTTP 어댑터다.
 *
 * <p>Entity나 HTTP 응답 객체를 상위 계층에 노출하지 않으며 요청 전후에 관찰 생성 계약의 Bean Validation을 적용한다. 아동 표현이 담길 수 있는
 * 요청·응답 원문과 내부 토큰은 로그나 Exception 메시지에 남기지 않는다.
 */
public final class RestClientAiObservationClient implements AiObservationClient {

  private static final TypeReference<ObservationGenerationResult> RESULT_TYPE =
      new TypeReference<>() {};

  private final RestClient restClient;
  private final String endpointPath;
  private final String internalToken;
  private final Validator validator;
  private final ObjectMapper objectMapper;

  RestClientAiObservationClient(
      RestClient restClient,
      String endpointPath,
      String internalToken,
      Validator validator,
      ObjectMapper objectMapper) {
    this.restClient = restClient;
    this.endpointPath = endpointPath;
    if (internalToken == null || internalToken.isBlank()) {
      throw new IllegalArgumentException("internalToken must not be blank");
    }
    this.internalToken = internalToken;
    this.validator = validator;
    this.objectMapper = Objects.requireNonNull(objectMapper, "objectMapper must not be null");
  }

  /**
   * 정본 내부 Endpoint에 인증된 최종 분석 관찰 생성 요청을 전송한다.
   *
   * @param request 최종 분석 관찰 생성 요청
   * @return 검증된 관찰 리포트 생성 결과
   * @throws AiObservationClientException 요청 생성, 통신 또는 응답 검증에 실패한 경우
   */
  @Override
  public ObservationGeneration generate(ObservationGenerationRequest request) {
    if (request == null
        || !"FINAL".equals(request.analysisType())
        || !validator.validate(request).isEmpty()) {
      throw new AiObservationClientException(AiObservationClientException.Type.REQUEST_FAILED);
    }

    // 본문을 문자열로 먼저 받아 두고 계약 스키마로 읽는다. 곧바로 타입으로 받으면 스키마에 없는
    //   필드가 읽는 순간 사라져, 무엇이 버려졌는지 확인할 방법이 없다(S15P11B209-980).
    String rawJson;
    ObservationGenerationResult response;
    try {
      rawJson =
          restClient
              .post()
              .uri(endpointPath)
              .header("X-Internal-Token", internalToken)
              .header("X-Request-Id", request.requestId())
              .contentType(MediaType.APPLICATION_JSON)
              .body(request)
              .retrieve()
              .onStatus(
                  status -> !status.is2xxSuccessful(),
                  (clientRequest, clientResponse) -> {
                    throw new AiObservationClientException(
                        clientResponse.getStatusCode().is5xxServerError()
                            ? AiObservationClientException.Type.SERVER_ERROR
                            : AiObservationClientException.Type.REQUEST_FAILED);
                  })
              .body(String.class);
      response = rawJson == null ? null : readResult(rawJson);
    } catch (AiObservationClientException exception) {
      throw exception;
    } catch (JsonProcessingException exception) {
      // 본문 원문은 아이 표현을 담을 수 있어 예외 메시지·로그에 싣지 않는다.
      throw new AiObservationClientException(
          AiObservationClientException.Type.INVALID_RESPONSE, exception);
    } catch (ResourceAccessException exception) {
      throw new AiObservationClientException(
          hasTimeoutCause(exception)
              ? AiObservationClientException.Type.TIMEOUT
              : AiObservationClientException.Type.REQUEST_FAILED,
          exception);
    } catch (RestClientException exception) {
      throw new AiObservationClientException(
          AiObservationClientException.Type.INVALID_RESPONSE, exception);
    }

    if (response == null
        || !Objects.equals(request.requestId(), response.requestId())
        || response.observationDraft() == null
        || response.conversationSummary() == null
        || isBlank(response.observationDraft().disclaimer())
        || isBlank(response.limitationsText())
        || !validator.validate(response).isEmpty()) {
      throw new AiObservationClientException(AiObservationClientException.Type.INVALID_RESPONSE);
    }
    return new ObservationGeneration(response, rawJson);
  }

  /**
   * 응답 본문을 계약 스키마로 읽는다. <b>스키마에 없는 필드가 있어도 실패하지 않는다.</b>
   *
   * <p>AI 가 계약에 없는 필드를 하나 더 보내는 순간 리포트 생성이 통째로 실패하면 안 된다. 우리가 못 읽는 필드는 그냥 안 쓰면 되고, 무엇이 왔는지는 원문에 남는다
   * (S15P11B209-980).
   *
   * <p>주입된 Mapper 설정에 기대지 않고 여기서 못박는다 — 전역 Jackson 설정이 바뀌면 조용히 실패 모드가 달라진다.
   */
  private ObservationGenerationResult readResult(String rawJson) throws JsonProcessingException {
    return objectMapper
        .reader()
        .without(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
        .forType(RESULT_TYPE)
        .readValue(rawJson);
  }

  private boolean isBlank(String value) {
    return value == null || value.isBlank();
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
