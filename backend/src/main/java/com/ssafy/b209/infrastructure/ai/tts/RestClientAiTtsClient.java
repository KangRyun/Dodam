package com.ssafy.b209.infrastructure.ai.tts;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.ssafy.b209.conversation.dto.TtsToneProfile;
import java.math.BigDecimal;
import java.net.SocketTimeoutException;
import java.net.http.HttpTimeoutException;
import java.util.Base64;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * Spring RestClient로 질문 TTS 합성 JSON 계약을 호출하는 HTTP 어댑터다.
 *
 * <p>as-built 계약({@code POST /internal/ai/v1/speech/synthesis}, 헤더 {@code X-Internal-Token})에 맞춰
 * {@code audioBase64}·{@code audioFormat}을 받아 Byte로 복원한다. 합성 텍스트와 음성 Byte, 내부 토큰은 로그나 Exception
 * 메시지에 남기지 않는다.
 */
public final class RestClientAiTtsClient implements AiTtsClient {

  private static final String AUDIO_FORMAT = "mp3";

  private final RestClient restClient;
  private final String endpointPath;
  private final String internalToken;

  RestClientAiTtsClient(RestClient restClient, String endpointPath, String internalToken) {
    this.restClient = restClient;
    this.endpointPath = endpointPath;
    if (internalToken == null || internalToken.isBlank()) {
      throw new IllegalArgumentException("internalToken must not be blank");
    }
    this.internalToken = internalToken;
  }

  /**
   * as-built 내부 Endpoint에 인증된 질문 합성 요청을 전송한다.
   *
   * @param command 합성할 텍스트와 음색·속도 요청
   * @return 복원된 음성 Byte와 {@code mp3} 형식
   * @throws AiTtsClientException 요청 생성, 통신 또는 응답 검증에 실패한 경우
   */
  @Override
  public TtsSynthesis synthesize(TtsSynthesisCommand command) {
    if (command == null || command.text() == null || command.text().isBlank()) {
      throw new AiTtsClientException(AiTtsClientException.Type.REQUEST_FAILED);
    }

    SynthesisHttpResponse response;
    try {
      response =
          restClient
              .post()
              .uri(endpointPath)
              .header("X-Internal-Token", internalToken)
              .header("X-Request-Id", UUID.randomUUID().toString())
              .contentType(MediaType.APPLICATION_JSON)
              .body(
                  new SynthesisHttpRequest(
                      command.text(), command.voice(), command.speed(), command.toneProfile()))
              .retrieve()
              .onStatus(
                  status -> !status.is2xxSuccessful(),
                  (clientRequest, clientResponse) -> {
                    throw new AiTtsClientException(
                        clientResponse.getStatusCode().is5xxServerError()
                            ? AiTtsClientException.Type.SERVER_ERROR
                            : AiTtsClientException.Type.REQUEST_FAILED);
                  })
              .body(SynthesisHttpResponse.class);
    } catch (AiTtsClientException exception) {
      throw exception;
    } catch (ResourceAccessException exception) {
      throw new AiTtsClientException(
          hasTimeoutCause(exception)
              ? AiTtsClientException.Type.TIMEOUT
              : AiTtsClientException.Type.REQUEST_FAILED,
          exception);
    } catch (RestClientException exception) {
      throw new AiTtsClientException(AiTtsClientException.Type.INVALID_RESPONSE, exception);
    }

    if (response == null
        || response.audioBase64() == null
        || response.audioBase64().isBlank()
        || !AUDIO_FORMAT.equalsIgnoreCase(response.audioFormat())) {
      throw new AiTtsClientException(AiTtsClientException.Type.INVALID_RESPONSE);
    }
    byte[] audio;
    try {
      audio = Base64.getDecoder().decode(response.audioBase64());
    } catch (IllegalArgumentException exception) {
      throw new AiTtsClientException(AiTtsClientException.Type.INVALID_RESPONSE, exception);
    }
    if (audio.length == 0) {
      throw new AiTtsClientException(AiTtsClientException.Type.INVALID_RESPONSE);
    }
    return new TtsSynthesis(audio, AUDIO_FORMAT);
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

  private record SynthesisHttpRequest(
      String text, String voice, BigDecimal speed, TtsToneProfile toneProfile) {}

  @JsonIgnoreProperties(ignoreUnknown = true)
  private record SynthesisHttpResponse(String audioBase64, String audioFormat) {}
}
