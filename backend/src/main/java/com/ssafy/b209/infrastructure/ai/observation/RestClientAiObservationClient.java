package com.ssafy.b209.infrastructure.ai.observation;

import java.io.IOException;
import static java.nio.charset.StandardCharsets.UTF_8;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.report.dto.ObservationGeneration;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validator;
import java.net.SocketTimeoutException;
import java.net.http.HttpTimeoutException;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

  private static final Logger logger =
      LoggerFactory.getLogger(RestClientAiObservationClient.class);

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
                    // 4xx 본문에는 AI가 값 echo 를 지운 위반 필드 위치(loc·type)가 담겨 있다
                    //   (ai/main.py validation_error_without_echo). 안 읽고 접으면 어느 필드가
                    //   계약을 어겼는지 알 수 없다 — 리포트 172(1006)가 그렇게 이틀치 진단을
                    //   헛돌게 했다. 990이 INVALID_RESPONSE 세 경로를 연 것과 같은 결이며,
                    //   본문은 이미 비식별이라 그대로 남겨도 아이 표현이 새지 않는다.
                    String body = null;
                    try {
                      body = new String(clientResponse.getBody().readAllBytes(), UTF_8);
                    } catch (IOException ignored) {
                      // 본문을 못 읽어도 상태 코드 로그는 남긴다.
                    }
                    logger.warn(
                        "관찰 요청 거절 — status={} body={} (requestId={})",
                        clientResponse.getStatusCode().value(),
                        body,
                        request.requestId());
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
      //   다만 **무엇이 실패했는지**는 남긴다 — 없으면 INVALID_RESPONSE 세 경로를 구분할 수 없다(989).
      logger.warn("관찰 응답 파싱 실패 — 계약 스키마로 읽지 못했다 (requestId={})", request.requestId());
      throw new AiObservationClientException(
          AiObservationClientException.Type.INVALID_RESPONSE, exception);
    } catch (ResourceAccessException exception) {
      boolean timeout = hasTimeoutCause(exception);
      logger.warn(
          "관찰 요청 통신 실패 — timeout={} exception={} (requestId={})",
          timeout,
          exception.getClass().getSimpleName(),
          request.requestId());
      throw new AiObservationClientException(
          timeout
              ? AiObservationClientException.Type.TIMEOUT
              : AiObservationClientException.Type.REQUEST_FAILED,
          exception);
    } catch (RestClientException exception) {
      // ⚠️ 여기로 오는 것은 통신 계열인데 타입이 INVALID_RESPONSE 다. 실제로 어떤 예외였는지
      //   남기지 않으면 "응답 형식이 틀렸다"로 오독한다 — 2026-08-06 진단이 그렇게 헛돌았다.
      logger.warn(
          "관찰 요청 RestClient 실패 — exception={} (requestId={})",
          exception.getClass().getSimpleName(),
          request.requestId());
      throw new AiObservationClientException(
          AiObservationClientException.Type.INVALID_RESPONSE, exception);
    }

    String rejection = rejectionReason(request, response);
    if (rejection != null) {
      logger.warn("관찰 응답 거부 — {} (requestId={})", rejection, request.requestId());
      throw new AiObservationClientException(AiObservationClientException.Type.INVALID_RESPONSE);
    }
    return new ObservationGeneration(response, rawJson);
  }

  /**
   * 응답을 거부할 이유를 찾는다. 통과하면 {@code null}.
   *
   * <p>조건을 하나로 묶어 두면 어디서 걸렸는지 알 수 없어 진단이 막힌다(989). 값은 절대 담지 않는다 — 아이 표현이 섞이므로 <b>필드 이름만</b> 남긴다.
   *
   * @param request 검증 기준이 되는 요청
   * @param response 검증 대상 응답이며 {@code null}일 수 있다
   * @return 거부 사유 문구이며 통과하면 {@code null}
   */
  private String rejectionReason(
      ObservationGenerationRequest request, ObservationGenerationResult response) {
    if (response == null) {
      return "응답 본문이 비어 있다";
    }
    if (!Objects.equals(request.requestId(), response.requestId())) {
      return "requestId 불일치";
    }
    if (response.observationDraft() == null) {
      return "observationDraft 누락";
    }
    if (response.conversationSummary() == null) {
      return "conversationSummary 누락";
    }
    if (isBlank(response.observationDraft().disclaimer())) {
      return "observationDraft.disclaimer 비어 있음";
    }
    if (isBlank(response.limitationsText())) {
      return "limitationsText 비어 있음";
    }
    Set<ConstraintViolation<ObservationGenerationResult>> violations = validator.validate(response);
    if (!violations.isEmpty()) {
      // 위반 필드 경로만 모은다. 위반 값(getInvalidValue)은 담지 않는다.
      return "계약 검증 실패 — "
          + violations.stream()
              .map(violation -> violation.getPropertyPath().toString())
              .distinct()
              .sorted()
              .collect(Collectors.joining(", "));
    }
    return null;
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
