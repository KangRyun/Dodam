package com.ssafy.b209.infrastructure.ai;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.conversation.dto.AiQuestionRequest;
import com.ssafy.b209.conversation.dto.AiQuestionResponse;
import java.net.SocketTimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

class RestClientAiQuestionClientTest {

  @Test
  void classifiesOnlyTheContractSafetyErrorCodeAsSafetyBlocked() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    server
        .expect(requestTo("http://ai.test/internal/ai/v1/conversations/question"))
        .andRespond(
            withStatus(HttpStatus.UNPROCESSABLE_ENTITY)
                .body("{\"errorCode\":\"AI_SAFETY_POLICY_BLOCKED\"}")
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON));

    RestClientAiQuestionClient client =
        new RestClientAiQuestionClient(builder.build(), "token", new ObjectMapper());

    assertThatThrownBy(() -> client.generate(request(), "request-1"))
        .isInstanceOfSatisfying(
            AiQuestionClientException.class,
            exception ->
                org.assertj.core.api.Assertions.assertThat(exception.getType())
                    .isEqualTo(AiQuestionClientException.Type.SAFETY_POLICY_BLOCKED));
    server.verify();
  }

  @Test
  void serializesResolvedSubjectContextFieldsInCamelCase() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    server
        .expect(requestTo("http://ai.test/internal/ai/v1/conversations/question"))
        .andExpect(jsonPath("$.activityType").value("HTP"))
        .andExpect(jsonPath("$.drawingSubject").value("HOUSE"))
        .andExpect(jsonPath("$.askedObjectCodes[0]").value("TREE"))
        .andExpect(jsonPath("$.askedObjectCodes[1]").value("SUN"))
        .andRespond(
            withSuccess(
                "{\"questionText\":\"q\",\"questionPurpose\":\"OBJECT_DESCRIPTION\","
                    + "\"options\":null,\"targetObject\":null,\"fallbackUsed\":false,"
                    + "\"safetyResult\":{\"status\":\"PASSED\",\"ruleVersion\":\"safety-2026-07\","
                    + "\"blockReasonCode\":null},\"modelName\":\"m\",\"modelVersion\":\"v\","
                    + "\"promptVersion\":\"p\",\"processingTimeMs\":1}",
                org.springframework.http.MediaType.APPLICATION_JSON));

    RestClientAiQuestionClient client =
        new RestClientAiQuestionClient(builder.build(), "token", new ObjectMapper());

    client.generate(subjectContextRequest(), "request-1");
    server.verify();
  }

  @Test
  void classifiesOther422ResponsesAsGeneralAiErrors() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    server
        .expect(requestTo("http://ai.test/internal/ai/v1/conversations/question"))
        .andRespond(
            withStatus(HttpStatus.UNPROCESSABLE_ENTITY)
                .body("{\"errorCode\":\"INVALID_REQUEST\"}")
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON));

    RestClientAiQuestionClient client =
        new RestClientAiQuestionClient(builder.build(), "token", new ObjectMapper());

    assertThatThrownBy(() -> client.generate(request(), "request-1"))
        .isInstanceOfSatisfying(
            AiQuestionClientException.class,
            exception ->
                org.assertj.core.api.Assertions.assertThat(exception.getType())
                    .isEqualTo(AiQuestionClientException.Type.OTHER));
    server.verify();
  }

  @Test
  void retriesExactlyOnceForConfirmedConnectTimeout() {
    AtomicInteger attempts = new AtomicInteger();
    RestClientAiQuestionClient client =
        new TestClient(attempts, AiQuestionClientException.Type.CONNECTION_FAILURE);

    assertThatThrownBy(() -> client.generate(null, "request-1"))
        .isInstanceOf(AiQuestionClientException.class);

    org.assertj.core.api.Assertions.assertThat(attempts).hasValue(2);
  }

  @Test
  void classifiesConfirmedConnectTimeoutAsConnectionFailure() {
    AiQuestionClientException exception =
        RestClientAiQuestionClient.classifyResourceAccess(
            new ResourceAccessException(
                "AI request failed", new SocketTimeoutException("Connect timed out")));

    org.assertj.core.api.Assertions.assertThat(exception.getType())
        .isEqualTo(AiQuestionClientException.Type.CONNECTION_FAILURE);
  }

  @Test
  void doesNotRetryReadOrAmbiguousSocketTimeout() {
    AtomicInteger attempts = new AtomicInteger();
    RestClientAiQuestionClient client =
        new TestClient(attempts, AiQuestionClientException.Type.READ_TIMEOUT);

    assertThatThrownBy(() -> client.generate(null, "request-1"))
        .isInstanceOf(AiQuestionClientException.class);

    org.assertj.core.api.Assertions.assertThat(attempts).hasValue(1);
  }

  @Test
  void classifiesReadAndAmbiguousSocketTimeoutAsReadTimeout() {
    AiQuestionClientException readTimeout =
        RestClientAiQuestionClient.classifyResourceAccess(
            new ResourceAccessException(
                "AI request failed", new SocketTimeoutException("Read timed out")));
    AiQuestionClientException ambiguousTimeout =
        RestClientAiQuestionClient.classifyResourceAccess(
            new ResourceAccessException(
                "AI request failed", new SocketTimeoutException("timed out")));

    org.assertj.core.api.Assertions.assertThat(readTimeout.getType())
        .isEqualTo(AiQuestionClientException.Type.READ_TIMEOUT);
    org.assertj.core.api.Assertions.assertThat(ambiguousTimeout.getType())
        .isEqualTo(AiQuestionClientException.Type.READ_TIMEOUT);
  }

  private static final class TestClient extends RestClientAiQuestionClient {
    private final AtomicInteger attempts;
    private final AiQuestionClientException.Type failureType;

    private TestClient(AtomicInteger attempts, AiQuestionClientException.Type failureType) {
      super(RestClient.builder().build(), "token", new ObjectMapper());
      this.attempts = attempts;
      this.failureType = failureType;
    }

    @Override
    protected AiQuestionResponse requestOnce(AiQuestionRequest request, String requestId) {
      attempts.incrementAndGet();
      throw new AiQuestionClientException(failureType, new SocketTimeoutException("timed out"));
    }
  }

  private AiQuestionRequest request() {
    return new AiQuestionRequest(
        1L,
        9L,
        null,
        8,
        QuestionDifficulty.LOWER_ELEMENTARY,
        java.util.List.of(com.ssafy.b209.conversation.domain.ResponseMode.VOICE),
        0,
        10,
        java.util.List.of(),
        null, // drawingDescription — 선택 필드(S15P11B209-704)
        java.util.List.of(),
        "safety-2026-07",
        null,
        null,
        java.util.List.of());
  }

  private AiQuestionRequest subjectContextRequest() {
    return new AiQuestionRequest(
        1L,
        9L,
        null,
        8,
        QuestionDifficulty.LOWER_ELEMENTARY,
        java.util.List.of(com.ssafy.b209.conversation.domain.ResponseMode.VOICE),
        0,
        10,
        java.util.List.of(),
        null,
        java.util.List.of(),
        "safety-2026-07",
        "HTP",
        "HOUSE",
        java.util.List.of("TREE", "SUN"));
  }
}
