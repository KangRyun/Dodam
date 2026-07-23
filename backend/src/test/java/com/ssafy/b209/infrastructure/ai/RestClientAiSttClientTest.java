package com.ssafy.b209.infrastructure.ai;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.ExpectedCount.times;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;

import com.ssafy.b209.storage.audio.OpenedAudio;
import java.io.ByteArrayInputStream;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

/** 최신 내부 STT HTTP 경로, file multipart, 재시도·schema 분류를 검증한다. */
class RestClientAiSttClientTest {

  @Test
  void sendsInternalTokenAndFileMultipartRequest() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    server
        .expect(requestTo("http://ai.test/internal/ai/v1/speech/stt"))
        .andExpect(header("X-Internal-Token", "internal-token"))
        .andExpect(header("X-Request-Id", "request-1"))
        .andExpect(content().contentTypeCompatibleWith(MediaType.MULTIPART_FORM_DATA))
        .andExpect(content().string(org.hamcrest.Matchers.containsString("name=\"file\"")))
        .andRespond(
            withStatus(HttpStatus.OK)
                .contentType(MediaType.APPLICATION_JSON)
                .body(successResponse()));

    AiSttResponse response =
        new RestClientAiSttClient(builder.build(), "internal-token").transcribe(request());

    assertThat(response.text()).isEqualTo("sample transcription");
    assertThat(response.confidence()).isNull();
    server.verify();
  }

  @Test
  void retriesExactlyOnceForAiUpstreamErrorWithFreshAudioStream() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    server
        .expect(times(1), requestTo("http://ai.test/internal/ai/v1/speech/stt"))
        .andRespond(withStatus(HttpStatus.BAD_GATEWAY));
    server
        .expect(times(1), requestTo("http://ai.test/internal/ai/v1/speech/stt"))
        .andRespond(
            withStatus(HttpStatus.OK)
                .contentType(MediaType.APPLICATION_JSON)
                .body(successResponse()));

    AiSttResponse response =
        new RestClientAiSttClient(builder.build(), "token").transcribe(request());

    assertThat(response.modelName()).isEqualTo("whisper-1");
    server.verify();
  }

  @Test
  void doesNotRetryReadTimeout() {
    AtomicInteger attempts = new AtomicInteger();
    RestClientAiSttClient client = new TestClient(attempts, AiSttClientException.Type.READ_TIMEOUT);

    assertThatThrownBy(() -> client.transcribe(request())).isInstanceOf(AiSttClientException.class);

    assertThat(attempts).hasValue(1);
  }

  @Test
  void retriesExactlyOnceForConnectionFailure() {
    AtomicInteger attempts = new AtomicInteger();
    RestClientAiSttClient client =
        new TestClient(attempts, AiSttClientException.Type.CONNECTION_FAILURE);

    assertThatThrownBy(() -> client.transcribe(request())).isInstanceOf(AiSttClientException.class);

    assertThat(attempts).hasValue(2);
  }

  @Test
  void doesNotRetryInvalidRequest() {
    AtomicInteger attempts = new AtomicInteger();
    RestClientAiSttClient client =
        new TestClient(attempts, AiSttClientException.Type.INVALID_REQUEST);

    assertThatThrownBy(() -> client.transcribe(request())).isInstanceOf(AiSttClientException.class);

    assertThat(attempts).hasValue(1);
  }

  @Test
  void distinguishesConnectionTimeoutFromReadTimeout() {
    AiSttClientException exception =
        RestClientAiSttClient.classifyResourceAccess(
            new ResourceAccessException(
                "internal STT failed", new SocketTimeoutException("Connect timed out")));

    assertThat(exception.getType()).isEqualTo(AiSttClientException.Type.CONNECTION_FAILURE);
  }

  @Test
  void rejectsInvalidSuccessSchemaWithoutRetry() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    server
        .expect(times(1), requestTo("http://ai.test/internal/ai/v1/speech/stt"))
        .andRespond(
            withStatus(HttpStatus.OK)
                .contentType(MediaType.APPLICATION_JSON)
                .body("{\"text\":\"sample transcription\",\"confidence\":null}"));

    RestClientAiSttClient client = new RestClientAiSttClient(builder.build(), "token");

    assertThatThrownBy(() -> client.transcribe(request()))
        .isInstanceOfSatisfying(
            AiSttClientException.class,
            exception ->
                assertThat(exception.getType())
                    .isEqualTo(AiSttClientException.Type.RESPONSE_SCHEMA_INVALID));
    server.verify();
  }

  private AiSttRequest request() {
    return new AiSttRequest(
        () ->
            new OpenedAudio(
                new ByteArrayInputStream("audio".getBytes(StandardCharsets.UTF_8)), "voice.wav"),
        "request-1");
  }

  private String successResponse() {
    return """
        {"text":"sample transcription","confidence":null,"modelName":"whisper-1",
         "processingTimeMs":120}
        """;
  }

  private static final class TestClient extends RestClientAiSttClient {
    private final AtomicInteger attempts;
    private final AiSttClientException.Type type;

    private TestClient(AtomicInteger attempts, AiSttClientException.Type type) {
      super(RestClient.builder().build(), "token");
      this.attempts = attempts;
      this.type = type;
    }

    @Override
    protected AiSttResponse requestOnce(AiSttRequest request) {
      attempts.incrementAndGet();
      throw new AiSttClientException(type, new SocketTimeoutException("read timed out"));
    }
  }
}
