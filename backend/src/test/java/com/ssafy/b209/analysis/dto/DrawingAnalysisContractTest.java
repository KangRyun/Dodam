package com.ssafy.b209.analysis.dto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.exc.InvalidFormatException;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class DrawingAnalysisContractTest {

  private final JsonMapper objectMapper =
      JsonMapper.builder().addModule(new JavaTimeModule()).build();
  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

  @Test
  void serializesAndDeserializesRequestContract() throws Exception {
    DrawingAnalysisRequest request = validRequest();

    String json = objectMapper.writeValueAsString(request);
    DrawingAnalysisRequest restored = objectMapper.readValue(json, DrawingAnalysisRequest.class);

    assertThat(restored).isEqualTo(request);
    assertThat(json)
        .contains("\"requestId\":\"550e8400-e29b-41d4-a716-446655440000\"")
        .contains("\"storageKey\":\"drawings/2026/07/22/example.png\"")
        .contains("\"analysisType\":\"OBJECT_DETECTION\"")
        .doesNotContain("DrawingSession", "DrawingAsset");
  }

  @Test
  void serializesAndDeserializesSuccessfulResponse() throws Exception {
    DrawingAnalysisResponse response =
        new DrawingAnalysisResponse(
            "550e8400-e29b-41d4-a716-446655440000",
            DrawingAnalysisStatus.SUCCEEDED,
            new DrawingAnalysisModelResponse("yolo-model", "1.0"),
            List.of(
                new DrawingDetectionResponse(
                    "HOUSE",
                    new BigDecimal("0.93"),
                    new BoundingBoxResponse(
                        new BigDecimal("120.0"),
                        new BigDecimal("80.0"),
                        new BigDecimal("640.0"),
                        new BigDecimal("520.0")))),
            null,
            Instant.parse("2026-07-22T05:00:00Z"));

    String json = objectMapper.writeValueAsString(response);
    DrawingAnalysisResponse restored = objectMapper.readValue(json, DrawingAnalysisResponse.class);

    assertThat(restored).isEqualTo(response);
    assertThat(json).contains("\"status\":\"SUCCEEDED\"");
    assertThat(json).contains("\"processedAt\":\"2026-07-22T05:00:00Z\"");
    assertThat(validator.validate(restored)).isEmpty();
  }

  @Test
  void acceptsSuccessfulResponseWithNoDetections() {
    DrawingAnalysisResponse response =
        new DrawingAnalysisResponse(
            "request-1",
            DrawingAnalysisStatus.SUCCEEDED,
            new DrawingAnalysisModelResponse("yolo-model", "1.0"),
            List.of(),
            null,
            Instant.parse("2026-07-22T05:00:00Z"));

    assertThat(validator.validate(response)).isEmpty();
  }

  @Test
  void serializesAndDeserializesFailedResponse() throws Exception {
    DrawingAnalysisResponse response =
        new DrawingAnalysisResponse(
            "request-1",
            DrawingAnalysisStatus.FAILED,
            null,
            List.of(),
            new DrawingAnalysisErrorResponse("AI_ANALYSIS_FAILED", "그림 분석을 완료하지 못했습니다."),
            Instant.parse("2026-07-22T05:00:00Z"));

    String json = objectMapper.writeValueAsString(response);
    DrawingAnalysisResponse restored = objectMapper.readValue(json, DrawingAnalysisResponse.class);

    assertThat(restored).isEqualTo(response);
    assertThat(json).doesNotContain("stackTrace", "exception", "C:\\");
    assertThat(validator.validate(restored)).isEmpty();
  }

  @Test
  void usesFixedUpperSnakeCaseEnumValues() throws Exception {
    assertThat(objectMapper.writeValueAsString(DrawingAnalysisType.OBJECT_DETECTION))
        .isEqualTo("\"OBJECT_DETECTION\"");
    assertThat(DrawingAnalysisStatus.values())
        .extracting(Enum::name)
        .containsExactly("PENDING", "PROCESSING", "SUCCEEDED", "FAILED");
  }

  @Test
  void validatesConfidenceBoundaries() {
    DrawingDetectionResponse zero = validDetection(new BigDecimal("0.0"));
    DrawingDetectionResponse one = validDetection(new BigDecimal("1.0"));
    DrawingDetectionResponse belowZero = validDetection(new BigDecimal("-0.01"));
    DrawingDetectionResponse aboveOne = validDetection(new BigDecimal("1.01"));

    assertThat(validator.validate(zero)).isEmpty();
    assertThat(validator.validate(one)).isEmpty();
    assertThat(validator.validate(belowZero)).isNotEmpty();
    assertThat(validator.validate(aboveOne)).isNotEmpty();
  }

  @Test
  void validatesBoundingBoxCoordinatesAndSize() {
    BoundingBoxResponse valid = boundingBox("0", "0", "1", "1");
    BoundingBoxResponse negativeX = boundingBox("-0.01", "0", "1", "1");
    BoundingBoxResponse negativeY = boundingBox("0", "-0.01", "1", "1");
    BoundingBoxResponse zeroWidth = boundingBox("0", "0", "0", "1");
    BoundingBoxResponse zeroHeight = boundingBox("0", "0", "1", "0");

    assertThat(validator.validate(valid)).isEmpty();
    assertThat(validator.validate(negativeX)).isNotEmpty();
    assertThat(validator.validate(negativeY)).isNotEmpty();
    assertThat(validator.validate(zeroWidth)).isNotEmpty();
    assertThat(validator.validate(zeroHeight)).isNotEmpty();
  }

  @Test
  void rejectsMissingRequiredRequestFieldsAndUnsafeStorageReference() {
    DrawingAnalysisRequest missing = new DrawingAnalysisRequest(" ", null, 0L, null, null);
    DrawingImageReference absolutePath =
        new DrawingImageReference("C:/private/drawing.png", "image/png");
    DrawingImageReference parentTraversal =
        new DrawingImageReference("drawings/../private.png", "image/png");
    DrawingImageReference emptySegment =
        new DrawingImageReference("drawings//image.png", "image/png");
    DrawingImageReference currentDirectorySegment =
        new DrawingImageReference("drawings/./image.png", "image/png");
    DrawingImageReference trailingSeparator =
        new DrawingImageReference("drawings/image.png/", "image/png");
    DrawingImageReference unsupportedContentType =
        new DrawingImageReference("drawings/image.gif", "image/gif");

    assertThat(validator.validate(missing)).hasSize(5);
    assertThat(validator.validate(absolutePath)).isNotEmpty();
    assertThat(validator.validate(parentTraversal)).isNotEmpty();
    assertThat(validator.validate(emptySegment)).isNotEmpty();
    assertThat(validator.validate(currentDirectorySegment)).isNotEmpty();
    assertThat(validator.validate(trailingSeparator)).isNotEmpty();
    assertThat(validator.validate(unsupportedContentType)).isNotEmpty();
  }

  @Test
  void protectsResponseContractFromCallerListMutation() {
    List<DrawingDetectionResponse> detections = new ArrayList<>();
    DrawingAnalysisResponse response =
        new DrawingAnalysisResponse(
            "request-1",
            DrawingAnalysisStatus.FAILED,
            null,
            detections,
            new DrawingAnalysisErrorResponse("AI_ANALYSIS_FAILED", "그림 분석을 완료하지 못했습니다."),
            Instant.parse("2026-07-22T05:00:00Z"));

    detections.add(validDetection(new BigDecimal("0.5")));

    assertThat(response.detections()).isEmpty();
    assertThat(validator.validate(response)).isEmpty();
  }

  @Test
  void rejectsUnknownEnumValue() {
    String json =
        """
        {
          "requestId": "request-1",
          "drawingSessionId": 100,
          "drawingAssetId": 200,
          "imageReference": {
            "storageKey": "drawings/example.png",
            "contentType": "image/png"
          },
          "analysisType": "UNKNOWN_TYPE"
        }
        """;

    assertThatThrownBy(() -> objectMapper.readValue(json, DrawingAnalysisRequest.class))
        .isInstanceOf(InvalidFormatException.class);
  }

  @Test
  void doesNotIncludeJpaEntitiesInRequestContract() {
    assertThat(DrawingAnalysisRequest.class.getRecordComponents())
        .allMatch(
            component ->
                component.getType() != DrawingSession.class
                    && component.getType() != DrawingAsset.class);
    assertThat(DrawingImageReference.class.getRecordComponents())
        .allMatch(
            component ->
                component.getType() != DrawingSession.class
                    && component.getType() != DrawingAsset.class);
  }

  private DrawingAnalysisRequest validRequest() {
    return new DrawingAnalysisRequest(
        "550e8400-e29b-41d4-a716-446655440000",
        100L,
        200L,
        new DrawingImageReference("drawings/2026/07/22/example.png", "image/png"),
        DrawingAnalysisType.OBJECT_DETECTION);
  }

  private DrawingDetectionResponse validDetection(BigDecimal confidence) {
    return new DrawingDetectionResponse("HOUSE", confidence, boundingBox("0", "0", "1", "1"));
  }

  private BoundingBoxResponse boundingBox(String x, String y, String width, String height) {
    return new BoundingBoxResponse(
        new BigDecimal(x), new BigDecimal(y), new BigDecimal(width), new BigDecimal(height));
  }
}
