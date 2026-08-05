package com.ssafy.b209.infrastructure.ai.observation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import jakarta.validation.Validation;
import java.math.BigDecimal;
import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.mock.http.client.MockClientHttpRequest;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.client.RequestMatcher;
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
  void serializesBehaviorMetricsAsCamelCaseJson() {
    // AI 는 _CamelModel 이라 camelCase 로 받는다. 이름이 어긋나면 Pydantic 기본값(None)으로 조용히 떨어져
    //   [형식적 분석] 블록이 사라지고 아무도 알아채지 못한다.
    JsonNode[] body = new JsonNode[1];
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(captureBody(body))
        .andRespond(withSuccess(successResponse("request-1"), MediaType.APPLICATION_JSON));

    client.generate(requestWith(behaviorMetrics()));

    JsonNode metrics = body[0].get("behaviorMetrics");
    assertThat(metrics.get("drawingDurationMs").asLong()).isEqualTo(600_000L);
    assertThat(metrics.get("activeDrawingMs").asLong()).isEqualTo(240_000L);
    assertThat(metrics.get("pauseCount").asInt()).isEqualTo(4);
    assertThat(metrics.get("undoCount").asInt()).isEqualTo(2);
    assertThat(metrics.get("eraseCount").asInt()).isEqualTo(3);
    assertThat(metrics.get("toolChangeCount").asInt()).isEqualTo(1);
    assertThat(metrics.get("colorChangeCount").asInt()).isEqualTo(5);
    assertThat(metrics.get("pressureAvailable").asBoolean()).isTrue();
    assertThat(metrics.get("truncated").asBoolean()).isFalse();
    // AI BehaviorMetrics 와 필드 1:1 — 여기 없는 키를 보내면 계약이 어긋난 것이다.
    assertThat(metrics.fieldNames())
        .toIterable()
        .containsExactlyInAnyOrder(
            "drawingDurationMs",
            "activeDrawingMs",
            "pauseCount",
            "undoCount",
            "eraseCount",
            "toolChangeCount",
            "colorChangeCount",
            "pressureAvailable",
            "averagePressure",
            "truncated");
    server.verify();
  }

  @Test
  void serializesUnmeasuredCountsAsJsonNullNotZero() {
    // 🔴 0 으로 나가면 AI 가 "0번"이라는 관찰 사실로 적는다. 집계하지 못한 값과 0회는 JSON 에서도 달라야 한다.
    JsonNode[] body = new JsonNode[1];
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(captureBody(body))
        .andRespond(withSuccess(successResponse("request-1"), MediaType.APPLICATION_JSON));

    client.generate(
        requestWith(
            new ObservationGenerationRequest.BehaviorMetrics(
                null, null, null, null, 0, null, null, false, null, false)));

    JsonNode metrics = body[0].get("behaviorMetrics");
    assertThat(metrics.get("pauseCount").isNull()).isTrue();
    assertThat(metrics.get("drawingDurationMs").isNull()).isTrue();
    assertThat(metrics.get("activeDrawingMs").isNull()).isTrue();
    // 계약에 자리만 있고 집계기가 만들지 않는 값이다. 지어내지 않는다.
    assertThat(metrics.get("averagePressure").isNull()).isTrue();
    // 실제로 0회 관찰된 값은 0으로 나간다 — null 과 구분된다.
    assertThat(metrics.get("eraseCount").asInt()).isZero();
    server.verify();
  }

  @Test
  void sendsBehaviorMetricsAsJsonNullWhenNothingWasAggregated() {
    // Pydantic 은 명시 null 과 키 누락을 모두 None 으로 받으므로 구 AI 배포본과도 호환된다.
    //   명시 null 로 보내면 "새 BE 인데 집계 못 함"과 "구 BE 라 아예 안 보냄"을 로그에서 구분할 수 있다.
    JsonNode[] body = new JsonNode[1];
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(captureBody(body))
        .andRespond(withSuccess(successResponse("request-1"), MediaType.APPLICATION_JSON));

    client.generate(validRequest());

    assertThat(body[0].get("behaviorMetrics").isNull()).isTrue();
    server.verify();
  }

  @Test
  void serializesDetectionGeometryAndStringEvidenceIds() {
    // 근거 식별자를 숫자로 보내면 Pydantic 이 "Input should be a valid string" 으로 요청 전체를 거부한다.
    //   2026-08-05 운영에서 POST /internal/v1/observations 가 이 계열 불일치로 전량 422 였다.
    JsonNode[] body = new JsonNode[1];
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(captureBody(body))
        .andRespond(withSuccess(successResponse("request-1"), MediaType.APPLICATION_JSON));

    client.generate(requestWithDetection());

    JsonNode subject = body[0].get("subjectSummaries").get(0);
    assertThat(subject.get("observationEvidenceSourceId").isTextual()).isTrue();
    assertThat(subject.get("observationEvidenceSourceId").asText()).isEqualTo("900");
    JsonNode detected = subject.get("detectedObjects").get(0);
    assertThat(detected.get("evidenceSourceId").isTextual()).isTrue();
    assertThat(detected.get("evidenceSourceId").asText()).isEqualTo("910");
    assertThat(detected.get("objectCode").asText()).isEqualTo("HOUSE_DOOR");
    assertThat(detected.get("x").asDouble()).isEqualTo(0.1);
    assertThat(detected.get("y").asDouble()).isEqualTo(0.2);
    assertThat(detected.get("width").asDouble()).isEqualTo(0.3);
    assertThat(detected.get("height").asDouble()).isEqualTo(0.4);
    assertThat(detected.get("confidence").asDouble()).isEqualTo(0.91);
    // 저장된 areaRatio 가 없으면 null 이다 — width * height 로 계산해 채우지 않는다.
    assertThat(detected.get("areaRatio").isNull()).isTrue();
    assertThat(body[0].get("selectedEmotionRefs").get(0).get("evidenceSourceId").isTextual())
        .isTrue();
    assertThat(detected.fieldNames())
        .toIterable()
        .containsExactlyInAnyOrder(
            "evidenceSourceId",
            "objectCode",
            "x",
            "y",
            "width",
            "height",
            "areaRatio",
            "confidence");
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
            List.of(),
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
        List.of(),
        List.of());
  }

  /**
   * 실제로 전송된 JSON 본문을 붙잡아 둔다.
   *
   * <p>본문을 직접 파싱하는 이유는 {@code null} 과 {@code 0} 을 구분해 단언하기 위해서다. 경로 존재 여부만 보는 단언은 "0으로 나갔다"를 잡지
   * 못한다.
   */
  private RequestMatcher captureBody(JsonNode[] target) {
    return request -> {
      String body = ((MockClientHttpRequest) request).getBodyAsString();
      target[0] = new ObjectMapper().readTree(body);
    };
  }

  private ObservationGenerationRequest requestWith(
      ObservationGenerationRequest.BehaviorMetrics metrics) {
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
        List.of(),
        List.of(),
        metrics);
  }

  private ObservationGenerationRequest requestWithDetection() {
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
        List.of(
            new ObservationGenerationRequest.SubjectSummary(
                "HOUSE",
                "가운데에 집이 크게 그려져 있어요.",
                List.of("HOUSE_DOOR"),
                List.of(),
                "900",
                List.of(
                    new ObservationGenerationRequest.SubjectDetectedObject(
                        "910",
                        "HOUSE_DOOR",
                        new BigDecimal("0.100000"),
                        new BigDecimal("0.200000"),
                        new BigDecimal("0.300000"),
                        new BigDecimal("0.400000"),
                        null,
                        new BigDecimal("0.9100"))))),
        List.of(new ObservationGenerationRequest.SelectedEmotionRef("920", "HAPPY")),
        null);
  }

  private ObservationGenerationRequest.BehaviorMetrics behaviorMetrics() {
    return new ObservationGenerationRequest.BehaviorMetrics(
        600_000L, 240_000L, 4, 2, 3, 1, 5, true, null, false);
  }

  @Test
  void bindsSubjectReportsAndRagReferences() {
    // 이 두 필드는 AI 가 보내고 있었는데 수신 DTO 에 자리가 없어 Jackson 이 조용히 버렸다
    //   (FAIL_ON_UNKNOWN_PROPERTIES 기본값 false). 응답을 파싱해 실제로 값이 들어오는지 본다 —
    //   저장·조회만 검증하면 재료가 비어 있어도 전부 초록이다(S15P11B209-960).
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withSuccess(
                subjectReportResponse("request-1"),
                org.springframework.http.MediaType.APPLICATION_JSON));

    ObservationGenerationResult result = client.generate(validRequest());

    assertThat(result.subjectReports())
        .extracting(ObservationGenerationResult.SubjectReportDraft::subjectType)
        .containsExactly("HOUSE", "TREE");
    assertThat(result.subjectReports().get(0).visionObservations())
        .containsExactly("집을 가운데 크게 그렸어요.");
    // category 가 아니라 publicInterpretations 배열 인덱스다(875 §5-1).
    assertThat(result.subjectReports().get(0).interpretationRefs()).containsExactly(0);
    assertThat(result.subjectReports().get(1).interpretationRefs()).isEmpty();
    // 출처 표시는 라이선스 의무(KOGL-1)라 버려지면 안 된다.
    assertThat(result.ragReferences())
        .extracting(ObservationGenerationResult.RagReferenceDraft::title)
        .containsExactly("아동 미술 관찰 안내");
    server.verify();
  }

  @Test
  void keepsSubjectReportsEmptyWhenAiOmitsTheField() {
    // 필드 단위 롤아웃 안전 — 구 AI 배포본이 필드를 안 보내도 나머지 경로는 그대로 살아야 한다.
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withSuccess(
                successResponse("request-1"), org.springframework.http.MediaType.APPLICATION_JSON));

    ObservationGenerationResult result = client.generate(validRequest());

    assertThat(result.subjectReports()).isEmpty();
    assertThat(result.ragReferences()).isEmpty();
    server.verify();
  }

  private String subjectReportResponse(String requestId) {
    return successResponse(requestId)
        .replace(
            "\"limitationsText\": \"제한된 활동 데이터를 바탕으로 한 관찰 기록입니다.\"",
            """
            "limitationsText": "제한된 활동 데이터를 바탕으로 한 관찰 기록입니다.",
            "subjectReports": [
              {
                "subjectType": "HOUSE",
                "visionObservations": ["집을 가운데 크게 그렸어요."],
                "interpretationRefs": [0]
              },
              {
                "subjectType": "TREE",
                "visionObservations": ["나무를 왼쪽에 그렸어요."],
                "interpretationRefs": []
              }
            ],
            "ragReferences": [
              { "sourceId": "kogl-001", "title": "아동 미술 관찰 안내" }
            ]\
            """);
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
