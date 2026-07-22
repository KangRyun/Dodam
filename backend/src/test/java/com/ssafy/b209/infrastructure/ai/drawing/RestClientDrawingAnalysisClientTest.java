package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.ssafy.b209.analysis.dto.DrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.dto.DrawingImageReference;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.net.ConnectException;
import java.net.SocketTimeoutException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class RestClientDrawingAnalysisClientTest {

  private static final String ENDPOINT_PATH = "/internal/ai/v1/drawings/analysis";
  private static final String ENDPOINT_URL = "http://ai.test" + ENDPOINT_PATH;

  private MockRestServiceServer server;
  private DrawingAnalysisClient client;

  @BeforeEach
  void setUp() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    server = MockRestServiceServer.bindTo(builder).build();
    Validator validator = Validation.buildDefaultValidatorFactory().getValidator();
    client = new RestClientDrawingAnalysisClient(builder.build(), ENDPOINT_PATH, validator);
  }

  @Test
  void sendsContractJsonAndReturnsSuccessfulResponse() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(method(HttpMethod.POST))
        .andExpect(content().contentType(MediaType.APPLICATION_JSON))
        .andExpect(
            content()
                .json(
                    """
                    {
                      "requestId": "request-1",
                      "drawingSessionId": 100,
                      "drawingAssetId": 200,
                      "imageReference": {
                        "storageKey": "drawings/example.png",
                        "contentType": "image/png"
                      },
                      "analysisType": "OBJECT_DETECTION"
                    }
                    """))
        .andRespond(withSuccess(successResponseJson("detection"), MediaType.APPLICATION_JSON));

    DrawingAnalysisResponse response = client.analyze(validRequest());

    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(response.detections()).hasSize(1);
    server.verify();
  }

  @Test
  void acceptsSuccessfulResponseWithEmptyDetections() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(withSuccess(successResponseJson("empty"), MediaType.APPLICATION_JSON));

    DrawingAnalysisResponse response = client.analyze(validRequest());

    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.SUCCEEDED);
    assertThat(response.detections()).isEmpty();
    server.verify();
  }

  @Test
  void returnsContractualFailedResponseWithoutConvertingItToClientException() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(withSuccess(failedResponseJson(), MediaType.APPLICATION_JSON));

    DrawingAnalysisResponse response = client.analyze(validRequest());

    assertThat(response.status()).isEqualTo(DrawingAnalysisStatus.FAILED);
    assertThat(response.error().code()).isEqualTo("AI_ANALYSIS_FAILED");
    server.verify();
  }

  @Test
  void rejectsInvalidRequestBeforeSendingHttpRequest() {
    DrawingAnalysisRequest invalidRequest = new DrawingAnalysisRequest(" ", null, 0L, null, null);

    assertThatThrownBy(() -> client.analyze(invalidRequest))
        .isInstanceOfSatisfying(
            DrawingAnalysisClientException.class,
            exception ->
                assertThat(exception.getType())
                    .isEqualTo(DrawingAnalysisClientException.Type.REQUEST_FAILED));
    server.verify();
  }

  @Test
  void mapsClientAndServerHttpErrors() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withStatus(HttpStatus.BAD_REQUEST)
                .body("internal request details")
                .contentType(MediaType.TEXT_PLAIN));

    assertClientFailure(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    server.verify();

    setUp();
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withStatus(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("internal model stack trace")
                .contentType(MediaType.TEXT_PLAIN));

    assertClientFailure(DrawingAnalysisClientException.Type.SERVER_ERROR);
    server.verify();
  }

  @Test
  void rejectsRedirectResponseEvenWhenItsBodyMatchesTheContract() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withStatus(HttpStatus.FOUND)
                .body(successResponseJson("empty"))
                .contentType(MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    server.verify();
  }

  @Test
  void mapsConnectionFailure() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            request -> {
              throw new ConnectException("Connection refused by http://internal-ai:8000");
            });

    assertClientFailure(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    server.verify();
  }

  @Test
  void mapsConnectAndReadTimeouts() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            request -> {
              throw new SocketTimeoutException("Connect timed out");
            });

    assertClientFailure(DrawingAnalysisClientException.Type.TIMEOUT);
    server.verify();

    setUp();
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            request -> {
              throw new SocketTimeoutException("Read timed out");
            });

    assertClientFailure(DrawingAnalysisClientException.Type.TIMEOUT);
    server.verify();
  }

  @Test
  void rejectsEmptyResponseBody() {
    server.expect(requestTo(ENDPOINT_URL)).andRespond(withSuccess("", MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);
    server.verify();
  }

  @Test
  void rejectsMalformedJsonAndUnknownEnumWithoutExposingPayload() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(withSuccess("{\"secret\":", MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);
    server.verify();

    setUp();
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withSuccess(
                successResponseJson("empty").replace("SUCCEEDED", "UNKNOWN_STATUS"),
                MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);
    server.verify();
  }

  @Test
  void rejectsResponseThatViolatesBeanValidationContract() {
    String invalidResponse = successResponseJson("empty").replace("\"yolo-model\"", "\" \"");
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(withSuccess(invalidResponse, MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);
    server.verify();
  }

  @Test
  void rejectsResponseForAnotherRequestId() {
    String mismatchedResponse =
        successResponseJson("empty").replace("\"request-1\"", "\"another-request\"");
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(withSuccess(mismatchedResponse, MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);
    server.verify();
  }

  private DrawingAnalysisRequest validRequest() {
    return new DrawingAnalysisRequest(
        "request-1",
        100L,
        200L,
        new DrawingImageReference("drawings/example.png", "image/png"),
        DrawingAnalysisType.OBJECT_DETECTION);
  }

  private void assertClientFailure(DrawingAnalysisClientException.Type expectedType) {
    assertThatThrownBy(() -> client.analyze(validRequest()))
        .isInstanceOfSatisfying(
            DrawingAnalysisClientException.class,
            exception -> {
              assertThat(exception.getType()).isEqualTo(expectedType);
              assertThat(exception.getMessage()).isEqualTo(expectedType.name());
              assertThat(exception.getMessage())
                  .doesNotContain(
                      "internal request details",
                      "internal model stack trace",
                      "internal-ai",
                      "secret",
                      "drawings/example.png");
            });
  }

  private String successResponseJson(String detectionMode) {
    String detections =
        "empty".equals(detectionMode)
            ? "[]"
            : """
              [{
                "label": "HOUSE",
                "confidence": 0.93,
                "boundingBox": {"x": 120.0, "y": 80.0, "width": 640.0, "height": 520.0}
              }]
              """;
    return """
        {
          "requestId": "request-1",
          "status": "SUCCEEDED",
          "model": {"name": "yolo-model", "version": "1.0"},
          "detections": %s,
          "error": null,
          "processedAt": "2026-07-22T05:00:00Z"
        }
        """
        .formatted(detections);
  }

  private String failedResponseJson() {
    return """
        {
          "requestId": "request-1",
          "status": "FAILED",
          "model": null,
          "detections": [],
          "error": {
            "code": "AI_ANALYSIS_FAILED",
            "message": "그림 분석을 완료하지 못했습니다."
          },
          "processedAt": "2026-07-22T05:00:00Z"
        }
        """;
  }
}
