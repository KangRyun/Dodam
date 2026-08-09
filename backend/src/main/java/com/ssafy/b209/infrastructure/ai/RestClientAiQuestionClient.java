package com.ssafy.b209.infrastructure.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.dto.AiQuestionRequest;
import com.ssafy.b209.conversation.dto.AiQuestionResponse;
import java.net.SocketTimeoutException;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

/** 목표 endpoint만 호출하며 legacy Mock 경로나 응답 별칭을 허용하지 않는다. */
@Component
public class RestClientAiQuestionClient implements AiQuestionClient {

  private static final String QUESTION_PATH = "/internal/ai/v1/conversations/question";

  private final RestClient restClient;
  private final String internalToken;
  private final ObjectMapper objectMapper;

  @Autowired
  public RestClientAiQuestionClient(
      RestClient.Builder builder,
      @Value("${AI_BASE_URL:http://localhost:8000}") String baseUrl,
      @Value("${AI_INTERNAL_TOKEN:}") String internalToken,
      ObjectMapper objectMapper) {
    this(createRestClient(builder, baseUrl), internalToken, objectMapper);
  }

  private static RestClient createRestClient(RestClient.Builder builder, String baseUrl) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(Duration.ofSeconds(1));
    requestFactory.setReadTimeout(Duration.ofSeconds(15));
    return builder.baseUrl(baseUrl).requestFactory(requestFactory).build();
  }

  RestClientAiQuestionClient(
      RestClient restClient, String internalToken, ObjectMapper objectMapper) {
    this.restClient = restClient;
    this.internalToken = internalToken;
    this.objectMapper = objectMapper;
  }

  @Override
  public AiQuestionResponse generate(AiQuestionRequest request, String requestId) {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        return requestOnce(request, requestId);
      } catch (AiQuestionClientException exception) {
        if (exception.getType() != AiQuestionClientException.Type.CONNECTION_FAILURE
            || attempt == 1) {
          throw exception;
        }
      }
    }
    throw new AiQuestionClientException(AiQuestionClientException.Type.CONNECTION_FAILURE);
  }

  protected AiQuestionResponse requestOnce(AiQuestionRequest request, String requestId) {
    try {
      return restClient
          .post()
          .uri(QUESTION_PATH)
          .contentType(MediaType.APPLICATION_JSON)
          .header("X-Internal-Token", internalToken)
          .header("X-Request-Id", requestId)
          .body(request)
          .retrieve()
          .onStatus(
              status -> status.value() == 422,
              (clientRequest, clientResponse) -> {
                if (isSafetyPolicyBlocked(clientResponse)) {
                  throw new AiQuestionClientException(
                      AiQuestionClientException.Type.SAFETY_POLICY_BLOCKED);
                }
                throw new AiQuestionClientException(AiQuestionClientException.Type.OTHER);
              })
          .body(AiQuestionResponse.class);
    } catch (AiQuestionClientException exception) {
      throw exception;
    } catch (RestClientResponseException exception) {
      throw new AiQuestionClientException(AiQuestionClientException.Type.OTHER, exception);
    } catch (ResourceAccessException exception) {
      throw classifyResourceAccess(exception);
    } catch (RuntimeException exception) {
      throw new AiQuestionClientException(
          AiQuestionClientException.Type.RESPONSE_SCHEMA_INVALID, exception);
    }
  }

  static AiQuestionClientException classifyResourceAccess(ResourceAccessException exception) {
    if (hasConfirmedConnectTimeout(exception)) {
      return new AiQuestionClientException(
          AiQuestionClientException.Type.CONNECTION_FAILURE, exception);
    }
    if (hasSocketTimeout(exception)) {
      return new AiQuestionClientException(AiQuestionClientException.Type.READ_TIMEOUT, exception);
    }
    return new AiQuestionClientException(
        AiQuestionClientException.Type.CONNECTION_FAILURE, exception);
  }

  private boolean isSafetyPolicyBlocked(
      org.springframework.http.client.ClientHttpResponse response) {
    try {
      JsonNode body = objectMapper.readTree(response.getBody().readAllBytes());
      return body != null && "AI_SAFETY_POLICY_BLOCKED".equals(body.path("errorCode").asText());
    } catch (Exception ignored) {
      return false;
    }
  }

  private static boolean hasConfirmedConnectTimeout(Throwable throwable) {
    Throwable current = throwable;
    while (current != null) {
      String className = current.getClass().getSimpleName();
      String message = current.getMessage();
      if (className.contains("ConnectTimeout")
          || (current instanceof SocketTimeoutException
              && message != null
              && (message.contains("Connect timed out")
                  || message.contains("connect timed out")))) {
        return true;
      }
      current = current.getCause();
    }
    return false;
  }

  private static boolean hasSocketTimeout(Throwable throwable) {
    Throwable current = throwable;
    while (current != null) {
      if (current instanceof SocketTimeoutException) {
        return true;
      }
      current = current.getCause();
    }
    return false;
  }
}
