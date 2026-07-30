package com.ssafy.b209.infrastructure.ai.observation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import jakarta.validation.Validation;
import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class RestClientAiObservationClientTest {

  private static final String ENDPOINT_URL = "http://ai.test/internal/v1/observations";

  private MockRestServiceServer server;
  private AiObservationClient client;

  @BeforeEach
  void setUp() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    server = MockRestServiceServer.bindTo(builder).build();
    client =
        new RestClientAiObservationClient(
            builder.build(),
            "/internal/v1/observations",
            "internal-token",
            Validation.buildDefaultValidatorFactory().getValidator());
  }

  @Test
  void acceptsCanonicalSuccessResponseAndSendsInternalHeaders() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(header("X-Internal-Token", "internal-token"))
        .andExpect(header("X-Request-Id", "request-1"))
        .andRespond(withSuccess(successResponse("request-1"), MediaType.APPLICATION_JSON));

    ObservationGenerationResult result = client.generate(validRequest());

    assertThat(result.requestId()).isEqualTo("request-1");
    assertThat(result.modelName()).isEqualTo("observation-generator");
    assertThat(result.observationDraft().status()).isEqualTo("AI_DRAFT");
    assertThat(result.conversationSummary().emotionSource()).isEqualTo("SELECTED");
    assertThat(result.limitationsText()).isNotBlank();
    server.verify();
  }

  @Test
  void rejectsResponseForAnotherRequest() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(withSuccess(successResponse("other-request"), MediaType.APPLICATION_JSON));

    assertClientFailure(AiObservationClientException.Type.INVALID_RESPONSE);
    server.verify();
  }

  @Test
  void mapsClientAndServerErrorsWithoutExposingResponseBody() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withStatus(HttpStatus.UNPROCESSABLE_ENTITY)
                .body("private input details")
                .contentType(MediaType.TEXT_PLAIN));
    assertClientFailure(AiObservationClientException.Type.REQUEST_FAILED);
    server.verify();

    setUp();
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withStatus(HttpStatus.BAD_GATEWAY)
                .body("model stack trace")
                .contentType(MediaType.TEXT_PLAIN));
    assertClientFailure(AiObservationClientException.Type.SERVER_ERROR);
    server.verify();
  }

  @Test
  void mapsConnectionAndTimeoutFailures() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            request -> {
              throw new ConnectException("internal host");
            });
    assertClientFailure(AiObservationClientException.Type.REQUEST_FAILED);
    server.verify();

    setUp();
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            request -> {
              throw new SocketTimeoutException("read timed out");
            });
    assertClientFailure(AiObservationClientException.Type.TIMEOUT);
    server.verify();
  }

  @Test
  void rejectsMalformedOrContractInvalidResponse() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(withSuccess("{\"secret\":", MediaType.APPLICATION_JSON));
    assertClientFailure(AiObservationClientException.Type.INVALID_RESPONSE);
    server.verify();

    setUp();
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withSuccess(
                successResponse("request-1")
                    .replace("\"disclaimer\": \"본 결과는 진단이 아닙니다.\"", "\"disclaimer\": null"),
                MediaType.APPLICATION_JSON));
    assertClientFailure(AiObservationClientException.Type.INVALID_RESPONSE);
    server.verify();
  }

  @Test
  void rejectsNonFinalRequestBeforeHttp() {
    ObservationGenerationRequest intermediate =
        new ObservationGenerationRequest(
            "request-1",
            700L,
            100L,
            "INTERMEDIATE",
            "NORMAL",
            3,
            2,
            1,
            0,
            List.of("HAPPY"),
            null,
            null,
            List.of());

    assertThatThrownBy(() -> client.generate(intermediate))
        .isInstanceOfSatisfying(
            AiObservationClientException.class,
            exception ->
                assertThat(exception.getType())
                    .isEqualTo(AiObservationClientException.Type.REQUEST_FAILED));
    server.verify();
  }

  @Test
  void rejectsBlankInternalToken() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    assertThatThrownBy(
            () ->
                new RestClientAiObservationClient(
                    builder.build(),
                    "/internal/v1/observations",
                    " ",
                    Validation.buildDefaultValidatorFactory().getValidator()))
        .isInstanceOf(IllegalArgumentException.class);
  }

  private void assertClientFailure(AiObservationClientException.Type expectedType) {
    assertThatThrownBy(() -> client.generate(validRequest()))
        .isInstanceOfSatisfying(
            AiObservationClientException.class,
            exception -> {
              assertThat(exception.getType()).isEqualTo(expectedType);
              assertThat(exception.getMessage()).isEqualTo(expectedType.name());
              assertThat(exception.getMessage())
                  .doesNotContain(
                      "private input details", "model stack trace", "internal host", "secret");
            });
  }

  private ObservationGenerationRequest validRequest() {
    return new ObservationGenerationRequest(
        "request-1",
        700L,
        100L,
        "FINAL",
        "NORMAL",
        3,
        2,
        1,
        0,
        List.of("HAPPY"),
        "행복했어요",
        null,
        List.of());
  }

  private String successResponse(String requestId) {
    return """
        {
          "requestId": "%s",
          "modelName": "observation-generator",
          "modelVersion": "1.0",
          "confidence": 0.80,
          "observationDraft": {
            "status": "AI_DRAFT",
            "overallSummary": "그림 활동 관찰 요약입니다.",
            "positiveSignals": "표현에 몰입했습니다.",
            "attentionPoints": "추가 관찰이 도움이 될 수 있습니다.",
            "evidenceSummary": "그림 구성과 대화 응답에서 관찰됨",
            "guardianGuidance": "편안하게 이야기를 이어가 보세요.",
            "followUpQuestion": "가장 마음에 드는 부분이 어디야?",
            "expertReviewRequired": false,
            "disclaimer": "본 결과는 진단이 아닙니다.",
            "features": []
          },
          "conversationSummary": {
            "summaryText": "대화에서 자신의 경험을 표현했습니다.",
            "mainTopic": "오늘의 그림",
            "expressedEmotion": "즐거움",
            "emotionSource": "SELECTED",
            "representativeUtterance": "재미있었어요"
          },
          "activityNotes": [],
          "followUpGuides": [],
          "guardianQuestions": [],
          "limitationsText": "제한된 활동 데이터를 바탕으로 한 관찰 기록입니다."
        }
        """
        .formatted(requestId);
  }
}
