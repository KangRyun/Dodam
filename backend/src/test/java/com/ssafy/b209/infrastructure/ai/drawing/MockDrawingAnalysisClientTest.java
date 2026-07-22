package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.json.JsonMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.ssafy.b209.analysis.dto.DrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.DrawingImageReference;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

class MockDrawingAnalysisClientTest {

  private static final Instant PROCESSED_AT = Instant.parse("2026-07-22T05:00:00Z");
  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();
  private final MockDrawingAnalysisClient client =
      new MockDrawingAnalysisClient(validator, Clock.fixed(PROCESSED_AT, ZoneOffset.UTC));
  private final JsonMapper objectMapper =
      JsonMapper.builder().addModule(new JavaTimeModule()).build();

  @Test
  void returnsDeterministicSuccessfulAnalysis() {
    DrawingAnalysisRequest request = validRequest();

    DrawingAnalysisResponse response = client.analyze(request);

    assertThat(response.requestId()).isEqualTo(request.requestId());
    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(response.model().name()).isEqualTo("mock-drawing-detector");
    assertThat(response.model().version()).isEqualTo("1.0");
    assertThat(response.detections()).hasSize(2);
    assertThat(response.detections())
        .extracting(detection -> detection.label())
        .containsExactly("HOUSE", "TREE");
    assertThat(response.detections())
        .extracting(detection -> detection.confidence())
        .containsExactly(new BigDecimal("0.95"), new BigDecimal("0.91"));
    assertThat(response.detections().get(0).boundingBox().x()).isEqualByComparingTo("120.0");
    assertThat(response.detections().get(0).boundingBox().y()).isEqualByComparingTo("80.0");
    assertThat(response.detections().get(0).boundingBox().width()).isEqualByComparingTo("640.0");
    assertThat(response.detections().get(0).boundingBox().height()).isEqualByComparingTo("520.0");
    assertThat(response.detections().get(1).boundingBox().x()).isEqualByComparingTo("820.0");
    assertThat(response.detections().get(1).boundingBox().y()).isEqualByComparingTo("120.0");
    assertThat(response.detections().get(1).boundingBox().width()).isEqualByComparingTo("380.0");
    assertThat(response.detections().get(1).boundingBox().height()).isEqualByComparingTo("700.0");
    assertThat(response.error()).isNull();
    assertThat(response.processedAt()).isEqualTo(PROCESSED_AT);
    assertThat(validator.validate(response)).isEmpty();
  }

  @Test
  void returnsTheSameImmutableResultForTheSameRequest() {
    DrawingAnalysisResponse first = client.analyze(validRequest());
    DrawingAnalysisResponse second = client.analyze(validRequest());

    assertThat(second).isEqualTo(first);
    assertThatThrownBy(() -> first.detections().add(first.detections().get(0)))
        .isInstanceOf(UnsupportedOperationException.class);
  }

  @Test
  void rejectsNullAndContractViolatingRequests() {
    List<DrawingAnalysisRequest> invalidRequests =
        List.of(
            new DrawingAnalysisRequest(
                " ", 100L, 200L, validImageReference(), DrawingAnalysisType.OBJECT_DETECTION),
            new DrawingAnalysisRequest(
                "request-1", 0L, 200L, validImageReference(), DrawingAnalysisType.OBJECT_DETECTION),
            new DrawingAnalysisRequest(
                "request-1",
                100L,
                null,
                validImageReference(),
                DrawingAnalysisType.OBJECT_DETECTION),
            new DrawingAnalysisRequest(
                "request-1", 100L, 200L, null, DrawingAnalysisType.OBJECT_DETECTION),
            new DrawingAnalysisRequest("request-1", 100L, 200L, validImageReference(), null));

    assertRequestFailure(null);
    invalidRequests.forEach(this::assertRequestFailure);
  }

  @Test
  void serializesAndDeserializesUsingTheExistingContract() throws Exception {
    DrawingAnalysisResponse response = client.analyze(validRequest());

    String json = objectMapper.writeValueAsString(response);
    DrawingAnalysisResponse restored = objectMapper.readValue(json, DrawingAnalysisResponse.class);

    assertThat(restored).isEqualTo(response);
    assertThat(json)
        .contains("\"status\":\"SUCCEEDED\"")
        .contains("\"label\":\"HOUSE\"")
        .contains("\"label\":\"TREE\"")
        .doesNotContain("storageKey", "C:\\", "http://", "https://");
    assertThat(validator.validate(restored)).isEmpty();
  }

  @Test
  void hasNoHttpClientDependency() {
    assertThat(MockDrawingAnalysisClient.class.getDeclaredFields())
        .extracting(field -> field.getType())
        .noneMatch(RestClient.class::isAssignableFrom);
  }

  private void assertRequestFailure(DrawingAnalysisRequest request) {
    assertThatThrownBy(() -> client.analyze(request))
        .isInstanceOfSatisfying(
            DrawingAnalysisClientException.class,
            exception ->
                assertThat(exception.getType())
                    .isEqualTo(DrawingAnalysisClientException.Type.REQUEST_FAILED));
  }

  private DrawingAnalysisRequest validRequest() {
    return new DrawingAnalysisRequest(
        "550e8400-e29b-41d4-a716-446655440000",
        100L,
        200L,
        validImageReference(),
        DrawingAnalysisType.OBJECT_DETECTION);
  }

  private DrawingImageReference validImageReference() {
    return new DrawingImageReference("drawings/2026/07/22/example.png", "image/png");
  }
}
