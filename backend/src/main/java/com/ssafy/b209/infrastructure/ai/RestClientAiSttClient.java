package com.ssafy.b209.infrastructure.ai;

import com.ssafy.b209.storage.audio.OpenedAudio;
import java.io.IOException;
import java.net.SocketTimeoutException;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

/**
 * 레거시 음성 경로를 사용하지 않고 최신 내부 STT multipart 계약만 호출하는 HTTP Client다.
 *
 * <p>연결 오류와 502만 한 번 재시도한다. read timeout은 음성 중복 처리를 막기 위해 자동 재전송하지 않는다.
 */
@Component
public class RestClientAiSttClient implements AiSttClient {
  private static final String STT_PATH = "/internal/ai/v1/speech/stt";

  private final RestClient restClient;
  private final String internalToken;

  /**
   * 환경 변수 기반 내부 AI 주소·토큰으로 Client를 만든다.
   *
   * @param builder Spring 공용 RestClient builder
   * @param baseUrl AI 내부 base URL
   * @param internalToken 로그에 기록하지 않는 내부 인증 토큰
   */
  @Autowired
  public RestClientAiSttClient(
      RestClient.Builder builder,
      @Value("${AI_BASE_URL:http://localhost:8000}") String baseUrl,
      @Value("${AI_INTERNAL_TOKEN:}") String internalToken) {
    this(createRestClient(builder, baseUrl), internalToken);
  }

  RestClientAiSttClient(RestClient restClient, String internalToken) {
    this.restClient = restClient;
    this.internalToken = internalToken;
  }

  /** {@inheritDoc} */
  @Override
  public AiSttResponse transcribe(AiSttRequest request) {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        AiSttResponse response = requestOnce(request);
        if (response == null) {
          throw new AiSttClientException(AiSttClientException.Type.RESPONSE_SCHEMA_INVALID);
        }
        response.validateContract();
        return response;
      } catch (AiSttClientException exception) {
        if (!isRetryable(exception) || attempt == 1) {
          throw exception;
        }
      }
    }
    throw new AiSttClientException(AiSttClientException.Type.CONNECTION_FAILURE);
  }

  /** 한 번의 HTTP STT 호출을 수행한다. 테스트에서는 재시도 경계를 검증하기 위해 확장할 수 있다. */
  protected AiSttResponse requestOnce(AiSttRequest request) {
    try (OpenedAudio audio = request.openAudio()) {
      return restClient
          .post()
          .uri(STT_PATH)
          .contentType(MediaType.MULTIPART_FORM_DATA)
          .header("X-Internal-Token", internalToken)
          .header("X-Request-Id", request.requestId())
          .body(multipart(audio))
          .retrieve()
          .onStatus(
              HttpStatusCode::isError,
              (clientRequest, clientResponse) -> {
                throw mapErrorStatus(clientResponse.getStatusCode().value());
              })
          .body(AiSttResponse.class);
    } catch (AiSttClientException exception) {
      throw exception;
    } catch (IOException exception) {
      throw new AiSttClientException(AiSttClientException.Type.CONNECTION_FAILURE, exception);
    } catch (RestClientResponseException exception) {
      if (exception.getStatusCode().value() == 502) {
        throw new AiSttClientException(AiSttClientException.Type.AI_UPSTREAM_ERROR, exception);
      }
      throw new AiSttClientException(AiSttClientException.Type.OTHER, exception);
    } catch (ResourceAccessException exception) {
      throw classifyResourceAccess(exception);
    } catch (RuntimeException exception) {
      throw new AiSttClientException(AiSttClientException.Type.RESPONSE_SCHEMA_INVALID, exception);
    }
  }

  private MultiValueMap<String, Object> multipart(OpenedAudio audio) {
    MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
    HttpHeaders audioHeaders = new HttpHeaders();
    audioHeaders.setContentType(MediaType.APPLICATION_OCTET_STREAM);
    body.add(
        "file",
        new HttpEntity<>(resource(audio.inputStream(), audio.transferFilename()), audioHeaders));
    return body;
  }

  private InputStreamResource resource(java.io.InputStream inputStream, String transferFilename) {
    return new InputStreamResource(inputStream) {
      @Override
      public long contentLength() {
        // InputStreamResource 길이 추정은 Stream을 미리 소비하므로 multipart 전송에서는 금지한다.
        return -1;
      }

      @Override
      public String getFilename() {
        return transferFilename;
      }
    };
  }

  private boolean isRetryable(AiSttClientException exception) {
    return exception.getType() == AiSttClientException.Type.CONNECTION_FAILURE
        || exception.getType() == AiSttClientException.Type.AI_UPSTREAM_ERROR;
  }

  private AiSttClientException mapErrorStatus(int status) {
    return switch (status) {
      case 401 -> new AiSttClientException(AiSttClientException.Type.INVALID_INTERNAL_TOKEN);
      case 422 -> new AiSttClientException(AiSttClientException.Type.INVALID_REQUEST);
      case 502 -> new AiSttClientException(AiSttClientException.Type.AI_UPSTREAM_ERROR);
      default -> new AiSttClientException(AiSttClientException.Type.OTHER);
    };
  }

  private static RestClient createRestClient(RestClient.Builder builder, String baseUrl) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(Duration.ofSeconds(2));
    requestFactory.setReadTimeout(Duration.ofSeconds(90));
    return builder.baseUrl(baseUrl).requestFactory(requestFactory).build();
  }

  static AiSttClientException classifyResourceAccess(ResourceAccessException exception) {
    if (hasConfirmedConnectTimeout(exception)) {
      return new AiSttClientException(AiSttClientException.Type.CONNECTION_FAILURE, exception);
    }
    if (hasSocketTimeout(exception)) {
      return new AiSttClientException(AiSttClientException.Type.READ_TIMEOUT, exception);
    }
    return new AiSttClientException(AiSttClientException.Type.CONNECTION_FAILURE, exception);
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
