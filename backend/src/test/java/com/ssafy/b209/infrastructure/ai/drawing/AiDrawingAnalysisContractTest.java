package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.json.JsonMapper;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisRequest;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class AiDrawingAnalysisContractTest {

  private final JsonMapper objectMapper = JsonMapper.builder().build();
  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

  @Test
  void serializesCanonicalAnalysisRequest() throws Exception {
    AiDrawingAnalysisRequest request =
        AiDrawingAnalysisRequest.minimum(
            701L,
            100L,
            AiDrawingAnalysisRequest.AnalysisType.FINAL,
            new AiDrawingAnalysisRequest.DrawingInput(
                200L, "https://signed.example/drawing", "image/png", 1200, 800, "a".repeat(64)));

    String json = objectMapper.writeValueAsString(request);

    assertThat(json)
        .contains("\"analysisId\":701")
        .contains("\"drawingSessionId\":100")
        .contains("\"analysisType\":\"FINAL\"")
        .contains("\"signedUrl\":\"https://signed.example/drawing\"")
        .doesNotContain("requestId", "storageKey");
    assertThat(validator.validate(request)).isEmpty();
  }

  @Test
  void deserializesCanonicalPartialSuccessResponseWithNormalizedDetection() throws Exception {
    String json =
        """
        {
          "analysisId": 701,
          "status": "PARTIAL_SUCCESS",
          "modelInfo": {
            "objectDetection": {"name": "yolo", "version": "1.0.0"},
            "vision": null,
            "language": null,
            "knowledgeBaseVersion": null
          },
          "detectedObjects": [{
            "objectCode": "HOUSE",
            "objectName": "집",
            "confidence": 0.93,
            "boundingBox": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4},
            "areaRatio": 0.12,
            "detectionOrder": 0
          }],
          "visualFeatures": {"inkRatio": 0.25},
          "behaviorFeatures": {"pressureAvailable": false},
          "conversationSummary": null,
          "observationDraft": null,
          "evidenceReferences": [],
          "unusedInputs": [{
            "sourceType": "PRESSURE",
            "reasonCode": "DEVICE_NOT_SUPPORTED",
            "reasonDetail": "필압을 지원하지 않음",
            "retryable": false
          }],
          "warnings": ["PRESSURE_DATA_UNAVAILABLE"],
          "processingTimeMs": 3840
        }
        """;

    AiDrawingAnalysisResponse response =
        objectMapper.readValue(json, AiDrawingAnalysisResponse.class);

    assertThat(response.analysisId()).isEqualTo(701L);
    assertThat(response.status())
        .isEqualTo(AiDrawingAnalysisResponse.AnalysisStatus.PARTIAL_SUCCESS);
    assertThat(response.detectedObjects())
        .singleElement()
        .satisfies(
            detection -> {
              assertThat(detection.objectCode()).isEqualTo("HOUSE");
              assertThat(detection.objectName()).isEqualTo("집");
              assertThat(detection.boundingBox().width())
                  .isEqualByComparingTo(new BigDecimal("0.3"));
            });
    assertThat(response.unusedInputs()).hasSize(1);
    assertThat(response.warnings()).containsExactly("PRESSURE_DATA_UNAVAILABLE");
    assertThat(validator.validate(response)).isEmpty();
  }

  @Test
  void preservesNullableFeatureValuesFromCanonicalResponse() throws Exception {
    String json =
        """
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
          "visualFeatures": {"strokeThickness": null},
          "behaviorFeatures": {"pressureMean": null},
          "conversationSummary": null,
          "observationDraft": null,
          "evidenceReferences": [],
          "unusedInputs": [],
          "warnings": [],
          "processingTimeMs": 10
        }
        """;

    AiDrawingAnalysisResponse response =
        objectMapper.readValue(json, AiDrawingAnalysisResponse.class);

    assertThat(response.visualFeatures()).containsEntry("strokeThickness", null);
    assertThat(response.behaviorFeatures()).containsEntry("pressureMean", null);
  }

  @Test
  void rejectsBoundingBoxThatLeavesNormalizedCanvas() {
    AiDrawingAnalysisResponse.BoundingBox boundingBox =
        new AiDrawingAnalysisResponse.BoundingBox(
            new BigDecimal("0.8"), BigDecimal.ZERO, new BigDecimal("0.3"), BigDecimal.ONE);

    assertThat(validator.validate(boundingBox)).isNotEmpty();
  }
}
