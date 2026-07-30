package com.ssafy.b209.infrastructure.ai.observation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.json.JsonMapper;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservedFeatureDraft;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.util.List;
import org.junit.jupiter.api.Test;

class MockAiObservationClientTest {

  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();
  private final MockAiObservationClient client = new MockAiObservationClient(validator);
  private final JsonMapper objectMapper = JsonMapper.builder().build();

  @Test
  void returnsDeterministicNonDiagnosticObservationDraft() {
    ObservationGenerationResult result = client.generate(validRequest());

    assertThat(result.requestId()).isEqualTo("request-1");
    assertThat(result.modelName()).isEqualTo("mock-observation-generator");
    assertThat(result.modelVersion()).isEqualTo("1.0");
    assertThat(result.observationDraft().status()).isEqualTo("AI_DRAFT");
    assertThat(result.observationDraft().disclaimer()).isNotBlank();
    assertThat(result.limitationsText()).isNotBlank();
    assertThat(result.observationDraft().expertReviewRequired()).isFalse();
    assertThat(result.conversationSummary().emotionSource()).isEqualTo("SELECTED");
  }

  @Test
  void keepsAllDraftFeaturesExpertOnly() {
    ObservationGenerationResult result = client.generate(validRequest());

    List<ObservedFeatureDraft> features = result.observationDraft().features();
    assertThat(features).isNotEmpty();
    assertThat(features)
        .extracting(ObservedFeatureDraft::visibilityScope)
        .containsOnly("EXPERT_ONLY");
    for (ObservedFeatureDraft feature : features) {
      assertThat(result.observationDraft().overallSummary()).doesNotContain(feature.description());
    }
  }

  @Test
  void echoesRepresentativeUtteranceFromRequest() {
    ObservationGenerationRequest request =
        new ObservationGenerationRequest(
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
            null,
            "즐거웠어요",
            List.of());

    ObservationGenerationResult result = client.generate(request);

    assertThat(result.conversationSummary().representativeUtterance()).isEqualTo("즐거웠어요");
  }

  @Test
  void returnsTheSameResultForTheSameRequest() {
    ObservationGenerationResult first = client.generate(validRequest());
    ObservationGenerationResult second = client.generate(validRequest());

    assertThat(second).isEqualTo(first);
  }

  @Test
  void rejectsNullContractViolatingAndNonFinalRequests() {
    assertRequestFailure(null);
    assertRequestFailure(
        new ObservationGenerationRequest(
            " ", 700L, 100L, "FINAL", null, 0, 0, 0, 0, List.of(), null, null, List.of()));
    assertRequestFailure(
        new ObservationGenerationRequest(
            "request-1", 0L, 100L, "FINAL", null, 0, 0, 0, 0, List.of(), null, null, List.of()));
    assertRequestFailure(
        new ObservationGenerationRequest(
            "request-1",
            700L,
            100L,
            "INTERMEDIATE",
            null,
            0,
            0,
            0,
            0,
            List.of(),
            null,
            null,
            List.of()));
    assertRequestFailure(
        new ObservationGenerationRequest(
            "request-1", 700L, 100L, "FINAL", null, -1, 0, 0, 0, List.of(), null, null, List.of()));
  }

  @Test
  void serializesResultWithoutSensitivePaths() throws Exception {
    ObservationGenerationResult result = client.generate(validRequest());

    String json = objectMapper.writeValueAsString(result);
    ObservationGenerationResult restored =
        objectMapper.readValue(json, ObservationGenerationResult.class);

    assertThat(restored).isEqualTo(result);
    assertThat(json).contains("\"status\":\"AI_DRAFT\"");
    assertThat(json).doesNotContain("C:\\", "http://", "https://", "storageKey");
  }

  private void assertRequestFailure(ObservationGenerationRequest request) {
    assertThatThrownBy(() -> client.generate(request))
        .isInstanceOfSatisfying(
            AiObservationClientException.class,
            exception ->
                assertThat(exception.getType())
                    .isEqualTo(AiObservationClientException.Type.REQUEST_FAILED));
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
}
