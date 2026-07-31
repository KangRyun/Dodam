package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import jakarta.validation.Validation;
import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.net.URI;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

@ExtendWith(OutputCaptureExtension.class)
class RestClientDrawingAnalysisClientTest {

  private static final String ENDPOINT_URL = "http://ai.test/internal/v1/analyses";

  private MockRestServiceServer server;
  private DrawingAnalysisClient client;

  @BeforeEach
  void setUp() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    server = MockRestServiceServer.bindTo(builder).build();
    client =
        new RestClientDrawingAnalysisClient(
            builder.build(),
            "/internal/v1/analyses",
            "internal-token",
            storageKey -> URI.create("https://signed.example/drawing"),
            Validation.buildDefaultValidatorFactory().getValidator());
  }

  @Test
  void acceptsCanonicalSuccessResponse() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andExpect(jsonPath("$.activityType").value("HTP"))
        .andExpect(jsonPath("$.drawingSubject").value("HOUSE"))
        .andExpect(jsonPath("$.triggerReason").value("USER_REQUEST"))
        .andRespond(withSuccess(successResponse(701L), MediaType.APPLICATION_JSON));

    var response = client.analyze(validCommand());

    assertThat(response.analysisId()).isEqualTo(701L);
    assertThat(response.detectedObjects()).isEmpty();
    server.verify();
  }

  @Test
  void rejectsResponseForAnotherAnalysis() {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(withSuccess(successResponse(999L), MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);
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
    assertClientFailure(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    server.verify();

    setUp();
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withStatus(HttpStatus.BAD_GATEWAY)
                .body("model stack trace")
                .contentType(MediaType.TEXT_PLAIN));
    assertClientFailure(DrawingAnalysisClientException.Type.SERVER_ERROR);
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
    assertClientFailure(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    server.verify();

    setUp();
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            request -> {
              throw new SocketTimeoutException("read timed out");
            });
    assertClientFailure(DrawingAnalysisClientException.Type.TIMEOUT);
    server.verify();
  }

  @Test
  void rejectsMalformedOrContractInvalidResponse() {
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
                successResponse(701L).replace("\"analysisId\": 701", "\"analysisId\": null"),
                MediaType.APPLICATION_JSON));
    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);
    server.verify();
  }

  @Test
  void logsMostSpecificCauseWithoutResponseBodyWhenDeserializationFails(CapturedOutput output) {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withSuccess(
                "{\"analysisId\":701,\"privateChildUtterance\":\"절대 기록하면 안 되는 원문\",",
                MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);

    assertThat(output)
        .contains("[735] AI 응답 역직렬화 실패:")
        .contains("Unexpected end-of-input")
        .doesNotContain("privateChildUtterance", "절대 기록하면 안 되는 원문");
    server.verify();
  }

  @Test
  void logsOnlySafeIdentifiersStatusAndViolationPathsWhenResponseValidationFails(
      CapturedOutput output) {
    server
        .expect(requestTo(ENDPOINT_URL))
        .andRespond(
            withSuccess(
                successResponse(999L)
                    .replace(
                        "\"name\": \"yolo\"",
                        "\"name\": \"\", \"privateChildUtterance\": \"절대 기록하면 안 되는 원문\""),
                MediaType.APPLICATION_JSON));

    assertClientFailure(DrawingAnalysisClientException.Type.INVALID_RESPONSE);

    assertThat(output)
        .contains("[735] AI 응답 검증 실패: reqId=701, respId=999, idMatch=false, status=SUCCESS")
        .contains("modelInfo.objectDetection.name:")
        .doesNotContain("privateChildUtterance", "절대 기록하면 안 되는 원문");
    server.verify();
  }

  @Test
  void rejectsRequestBeforeHttpWhenImageAccessIsUnavailable() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://ai.test");
    MockRestServiceServer localServer = MockRestServiceServer.bindTo(builder).build();
    DrawingAnalysisClient unavailableClient =
        new RestClientDrawingAnalysisClient(
            builder.build(),
            "/internal/v1/analyses",
            "internal-token",
            storageKey -> {
              throw new DrawingAnalysisClientException(
                  DrawingAnalysisClientException.Type.REQUEST_FAILED);
            },
            Validation.buildDefaultValidatorFactory().getValidator());

    assertThatThrownBy(() -> unavailableClient.analyze(validCommand()))
        .isInstanceOfSatisfying(
            DrawingAnalysisClientException.class,
            exception ->
                assertThat(exception.getType())
                    .isEqualTo(DrawingAnalysisClientException.Type.REQUEST_FAILED));
    localServer.verify();
  }

  private void assertClientFailure(DrawingAnalysisClientException.Type expectedType) {
    assertThatThrownBy(() -> client.analyze(validCommand()))
        .isInstanceOfSatisfying(
            DrawingAnalysisClientException.class,
            exception -> {
              assertThat(exception.getType()).isEqualTo(expectedType);
              assertThat(exception.getMessage()).isEqualTo(expectedType.name());
              assertThat(exception.getMessage())
                  .doesNotContain(
                      "private input details",
                      "model stack trace",
                      "internal host",
                      "secret",
                      "signed.example");
            });
  }

  private DrawingAnalysisClientCommand validCommand() {
    return new DrawingAnalysisClientCommand(
        "request-1",
        701L,
        100L,
        200L,
        DrawingAnalysisScope.FINAL,
        DrawingAnalysisActivityType.HTP,
        DrawingAnalysisSubject.HOUSE,
        DrawingInputMethod.CANVAS,
        "drawings/example.png",
        "image/png",
        null,
        null,
        "a".repeat(64));
  }

  private String successResponse(Long analysisId) {
    return """
        {
          "analysisId": %d,
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
        """
        .formatted(analysisId);
  }
}
