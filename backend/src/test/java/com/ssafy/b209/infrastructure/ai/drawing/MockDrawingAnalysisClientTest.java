package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import jakarta.validation.Validation;
import org.junit.jupiter.api.Test;

class MockDrawingAnalysisClientTest {

  private final MockDrawingAnalysisClient client =
      new MockDrawingAnalysisClient(Validation.buildDefaultValidatorFactory().getValidator());

  @Test
  void returnsDeterministicCanonicalPartialSuccess() {
    AiDrawingAnalysisResponse first = client.analyze(validCommand());
    AiDrawingAnalysisResponse second = client.analyze(validCommand());

    assertThat(first).isEqualTo(second);
    assertThat(first.status()).isEqualTo(AiDrawingAnalysisResponse.AnalysisStatus.PARTIAL_SUCCESS);
    assertThat(first.detectedObjects())
        .extracting(AiDrawingAnalysisResponse.DetectedObject::objectCode)
        .containsExactly("HOUSE", "TREE");
    assertThat(first.detectedObjects())
        .allSatisfy(
            detection -> {
              assertThat(detection.boundingBox().x())
                  .isBetween(java.math.BigDecimal.ZERO, java.math.BigDecimal.ONE);
              assertThat(detection.boundingBox().y())
                  .isBetween(java.math.BigDecimal.ZERO, java.math.BigDecimal.ONE);
            });
    assertThat(first.unusedInputs()).isNotEmpty();
    assertThat(first.warnings()).contains("MOCK_ANALYSIS_RESULT");
  }

  @Test
  void protectsResultListsFromMutation() {
    AiDrawingAnalysisResponse response = client.analyze(validCommand());

    assertThatThrownBy(() -> response.detectedObjects().clear())
        .isInstanceOf(UnsupportedOperationException.class);
    assertThatThrownBy(() -> response.warnings().clear())
        .isInstanceOf(UnsupportedOperationException.class);
  }

  @Test
  void rejectsInvalidCommand() {
    DrawingAnalysisClientCommand invalid =
        new DrawingAnalysisClientCommand(
            " ", null, 0L, 0L, null, "C:/private/image.png", "image/gif", null, null, null);

    assertThatThrownBy(() -> client.analyze(invalid))
        .isInstanceOfSatisfying(
            DrawingAnalysisClientException.class,
            exception ->
                assertThat(exception.getType())
                    .isEqualTo(DrawingAnalysisClientException.Type.REQUEST_FAILED));
  }

  private DrawingAnalysisClientCommand validCommand() {
    return new DrawingAnalysisClientCommand(
        "request-1",
        701L,
        100L,
        200L,
        DrawingAnalysisScope.FINAL,
        "drawings/example.png",
        "image/png",
        null,
        null,
        "a".repeat(64));
  }
}
