package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import jakarta.validation.Validation;
import java.net.URI;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class CanonicalRestClientDrawingAnalysisClientTest {

  @Test
  void sendsCanonicalRequestWithInternalAuthenticationAndCorrelationHeader() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    DrawingAnalysisClient client =
        new RestClientDrawingAnalysisClient(
            builder.build(),
            "/internal/v1/analyses",
            "internal-token",
            storageKey -> URI.create("https://signed.example/" + storageKey),
            Validation.buildDefaultValidatorFactory().getValidator());
    server
        .expect(requestTo("http://ai.test/internal/v1/analyses"))
        .andExpect(method(HttpMethod.POST))
        .andExpect(header("X-Internal-Token", "internal-token"))
        .andExpect(header("X-Request-Id", "request-1"))
        .andExpect(content().contentType(MediaType.APPLICATION_JSON))
        .andExpect(
            content()
                .json(
                    """
                    {
                      "analysisId": 701,
                      "drawingSessionId": 100,
                      "analysisType": "FINAL",
                      "drawing": {
                        "drawingAssetId": 200,
                        "signedUrl": "https://signed.example/drawings/example.png",
                        "mimeType": "image/png",
                        "width": 1200,
                        "height": 800,
                        "checksumSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                      }
                    }
                    """,
                    false))
        .andRespond(withSuccess(partialSuccessResponse(), MediaType.APPLICATION_JSON));

    AiDrawingAnalysisResponse response = client.analyze(validCommand());

    assertThat(response.analysisId()).isEqualTo(701L);
    assertThat(response.status())
        .isEqualTo(AiDrawingAnalysisResponse.AnalysisStatus.PARTIAL_SUCCESS);
    server.verify();
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
        1200,
        800,
        "a".repeat(64));
  }

  private String partialSuccessResponse() {
    return """
        {
          "analysisId": 701,
          "status": "PARTIAL_SUCCESS",
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
          "unusedInputs": [{
            "sourceType": "IMAGE_ACCESS",
            "reasonCode": "MODEL_NOT_READY",
            "reasonDetail": null,
            "retryable": true
          }],
          "warnings": ["OBJECT_DETECTION_NOT_READY"],
          "processingTimeMs": 10
        }
        """;
  }
}
