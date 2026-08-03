package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.service.StrokeBehaviorSummary;
import jakarta.validation.Validation;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.hamcrest.Matchers;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.mock.http.client.MockClientHttpRequest;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.client.RequestMatcher;
import org.springframework.web.client.RestClient;

/** 집계된 행동 요약이 §19.3 요청 JSON에 계약대로 실리는지 확인한다 (S15P11B209-772). */
class DrawingAnalysisBehaviorRequestTest {

  private static final String ENDPOINT_URL = "http://ai.test/internal/v1/analyses";

  /** 정본 §19.3 {@code behavior.summary} 필드 전체다. */
  private static final List<String> CONTRACT_SUMMARY_FIELDS =
      List.of(
          "drawingDurationMs",
          "activeDrawingMs",
          "pauseCount",
          "undoCount",
          "eraseCount",
          "toolChangeCount",
          "colorChangeCount",
          "pressureAvailable");

  private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

  private MockRestServiceServer server;

  @Test
  void sendsAggregatedBehaviorSummaryOnFinalAnalysis() {
    DrawingAnalysisClient client = clientReturning(Optional.of(summary()));
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(jsonPath("$.analysisType").value("FINAL"))
        .andExpect(jsonPath("$.behavior.strokeBatchUrls").isArray())
        .andExpect(jsonPath("$.behavior.strokeBatchUrls").isEmpty())
        .andExpect(jsonPath("$.behavior.summary.drawingDurationMs").value(600_000))
        .andExpect(jsonPath("$.behavior.summary.activeDrawingMs").value(420_000))
        .andExpect(jsonPath("$.behavior.summary.pauseCount").value(4))
        .andExpect(jsonPath("$.behavior.summary.undoCount").value(2))
        .andExpect(jsonPath("$.behavior.summary.eraseCount").value(3))
        .andExpect(jsonPath("$.behavior.summary.toolChangeCount").value(5))
        .andExpect(jsonPath("$.behavior.summary.colorChangeCount").value(6))
        .andExpect(jsonPath("$.behavior.summary.pressureAvailable").value(false))
        .andRespond(withSuccess(successResponse(), MediaType.APPLICATION_JSON));

    client.analyze(command(DrawingAnalysisScope.FINAL));

    server.verify();
  }

  @Test
  void sendsExactlyTheEightContractedSummaryFieldsAndNothingElse() {
    DrawingAnalysisClient client = clientReturning(Optional.of(summary()));
    server
        .expect(requestTo(ENDPOINT_URL))
        // 키 집합 자체를 고정한다. 필압 미지원을 0으로 채운 통계 항목이 새로 생기거나, 내부 전용 값(truncated)이
        //   계약으로 새어 나가거나, 계약 필드가 사라지면 전부 여기서 죽는다.
        .andExpect(summaryFieldNames())
        .andRespond(withSuccess(successResponse(), MediaType.APPLICATION_JSON));

    client.analyze(command(DrawingAnalysisScope.FINAL));

    server.verify();
  }

  @Test
  void omitsBehaviorEntirelyWhenSessionHasNoStrokeData() {
    DrawingAnalysisClient client = clientReturning(Optional.empty());
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(jsonPath("$.analysisType").value("FINAL"))
        // NON_NULL 이 적용된 최상위 Record라 behavior 는 null 로도 남지 않고 항목이 사라진다.
        .andExpect(jsonPath("$.behavior").doesNotExist())
        .andExpect(jsonPath("$.drawing.signedUrl").value("https://signed.example/drawing"))
        .andRespond(withSuccess(successResponse(), MediaType.APPLICATION_JSON));

    client.analyze(command(DrawingAnalysisScope.FINAL));

    server.verify();
  }

  /**
   * ⚠️ 현재 집계기({@code StrokeBehaviorSummaryService})는 8개 값을 항상 구체값으로 채우므로 이 상태는 프로덕션에서 만들어지지 않는다. 이
   * 테스트가 지키는 것은 집계 로직이 아니라 <b>Jackson 설정</b>이다 — 최상위 Record의 {@code @JsonInclude(NON_NULL)}이 중첩
   * {@code BehaviorSummary}까지 전파되면 측정 불가 값이 조용히 사라지는데, 그때 AI는 "값이 없다"와 "0"을 구분할 근거를 잃는다. 장차 집계기가
   * {@code null}을 내보내게 될 때를 위한 회귀 가드다.
   */
  @Test
  void keepsUnknownSummaryFieldsAsExplicitNullInsteadOfOmittingThem() {
    StrokeBehaviorSummary partial =
        new StrokeBehaviorSummary(null, 420_000L, null, 2, 3, null, null, true, false);
    DrawingAnalysisClient client = clientReturning(Optional.of(partial));
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(jsonPath("$.behavior.summary.activeDrawingMs").value(420_000))
        .andExpect(jsonPath("$.behavior.summary.undoCount").value(2))
        .andExpect(jsonPath("$.behavior.summary.pressureAvailable").value(true))
        // 키가 사라지는 것이 아니라 명시적 null 로 남아야 한다.
        .andExpect(summaryFieldNames())
        .andExpect(jsonPath("$.behavior.summary.drawingDurationMs").value(Matchers.nullValue()))
        .andExpect(jsonPath("$.behavior.summary.pauseCount").value(Matchers.nullValue()))
        .andRespond(withSuccess(successResponse(), MediaType.APPLICATION_JSON));

    client.analyze(command(DrawingAnalysisScope.FINAL));

    server.verify();
  }

  @Test
  void omitsBehaviorOnIntermediateAnalysis() {
    DrawingAnalysisClient client = clientReturning(Optional.of(summary()));
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(jsonPath("$.analysisType").value("INTERMEDIATE"))
        .andExpect(jsonPath("$.behavior").doesNotExist())
        .andRespond(withSuccess(successResponse(), MediaType.APPLICATION_JSON));

    client.analyze(command(DrawingAnalysisScope.INTERMEDIATE));

    server.verify();
  }

  @Test
  void completesAnalysisWithoutBehaviorWhenAggregationFails() {
    DrawingAnalysisClient client =
        clientWithProvider(
            drawingSessionId -> {
              throw new IllegalStateException("stroke storage unavailable");
            });
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(jsonPath("$.behavior").doesNotExist())
        .andRespond(withSuccess(successResponse(), MediaType.APPLICATION_JSON));

    assertThat(client.analyze(command(DrawingAnalysisScope.FINAL)).analysisId()).isEqualTo(701L);

    server.verify();
  }

  /**
   * 요청 body의 {@code behavior.summary} 키 집합이 계약 8필드와 정확히 같은지 확인한다.
   *
   * <p>개별 키에 {@code doesNotExist()}를 거는 방식은 계약 Record에 없는 이름을 지목하면 <b>어떤 변경으로도 실패할 수 없다.</b> 존재하는 키
   * 전체를 비교해야 필드 추가·삭제·오타를 모두 잡는다.
   */
  private static RequestMatcher summaryFieldNames() {
    return request -> {
      String body = ((MockClientHttpRequest) request).getBodyAsString();
      JsonNode summary = readTree(body).path("behavior").path("summary");
      List<String> actual = new ArrayList<>();
      summary.fieldNames().forEachRemaining(actual::add);
      assertThat(actual).containsExactlyInAnyOrderElementsOf(CONTRACT_SUMMARY_FIELDS);
    };
  }

  private static JsonNode readTree(String body) {
    try {
      return OBJECT_MAPPER.readTree(body);
    } catch (JsonProcessingException exception) {
      throw new AssertionError("요청 body를 JSON으로 읽지 못했다", exception);
    }
  }

  private DrawingAnalysisClient clientReturning(Optional<StrokeBehaviorSummary> summary) {
    return clientWithProvider(drawingSessionId -> summary);
  }

  private DrawingAnalysisClient clientWithProvider(DrawingBehaviorSummaryProvider provider) {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    server = MockRestServiceServer.bindTo(builder).build();
    return new RestClientDrawingAnalysisClient(
        builder.build(),
        "/internal/v1/analyses",
        "internal-token",
        storageKey -> URI.create("https://signed.example/drawing"),
        provider,
        Validation.buildDefaultValidatorFactory().getValidator());
  }

  private static StrokeBehaviorSummary summary() {
    return new StrokeBehaviorSummary(600_000L, 420_000L, 4, 2, 3, 5, 6, false, false);
  }

  private static DrawingAnalysisClientCommand command(DrawingAnalysisScope scope) {
    return new DrawingAnalysisClientCommand(
        "request-1",
        701L,
        100L,
        200L,
        scope,
        DrawingAnalysisActivityType.HTP,
        DrawingAnalysisSubject.HOUSE,
        DrawingInputMethod.CANVAS,
        "drawings/example.png",
        "image/png",
        1200,
        800,
        "a".repeat(64));
  }

  private static String successResponse() {
    return """
        {
          "analysisId": 701,
          "status": "SUCCESS",
          "modelInfo": {
            "objectDetection": {"name": "yolo", "version": "1.0.0"},
            "vision": null,
            "language": null,
            "knowledgeBaseVersion": null
          },
          "detectedObjects": [],
          "visualFeatures": {},
          "behaviorFeatures": {},
          "conversationSummary": null,
          "observationDraft": null,
          "evidenceReferences": [],
          "unusedInputs": [],
          "warnings": [],
          "processingTimeMs": 10
        }
        """;
  }
}
