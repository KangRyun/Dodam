package com.ssafy.b209.analysis.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class DrawingAnalysisContractTest {

  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

  @Test
  void validatesStorageIndependentClientCommand() {
    DrawingAnalysisClientCommand valid =
        new DrawingAnalysisClientCommand(
            "request-1",
            701L,
            100L,
            200L,
            DrawingAnalysisScope.FINAL,
            DrawingAnalysisActivityType.HTP,
            DrawingAnalysisSubject.HOUSE,
            "drawings/example.png",
            "image/png",
            1200,
            800,
            "a".repeat(64));
    DrawingAnalysisClientCommand unsafe =
        new DrawingAnalysisClientCommand(
            "request-1",
            701L,
            100L,
            200L,
            DrawingAnalysisScope.FINAL,
            DrawingAnalysisActivityType.ART_DIARY,
            null,
            "../private.png",
            "image/gif",
            null,
            null,
            null);

    assertThat(validator.validate(valid)).isEmpty();
    assertThat(validator.validate(unsafe)).isNotEmpty();
  }

  @Test
  void rejectsActivityAndSubjectMismatch() {
    DrawingAnalysisClientCommand htpWithoutSubject = command(DrawingAnalysisActivityType.HTP, null);
    DrawingAnalysisClientCommand artDiaryWithSubject =
        command(DrawingAnalysisActivityType.ART_DIARY, DrawingAnalysisSubject.PERSON);

    assertThat(validator.validate(htpWithoutSubject)).isNotEmpty();
    assertThat(validator.validate(artDiaryWithSubject)).isNotEmpty();
  }

  @Test
  void validatesPublicDetectionConfidenceAndBoundingBoxMinimums() {
    DrawingDetectionResponse valid =
        new DrawingDetectionResponse(
            "HOUSE",
            new BigDecimal("0.95"),
            new BoundingBoxResponse(
                BigDecimal.ZERO, BigDecimal.ZERO, new BigDecimal("0.4"), new BigDecimal("0.5")));
    DrawingDetectionResponse invalid =
        new DrawingDetectionResponse(
            "HOUSE",
            new BigDecimal("1.01"),
            new BoundingBoxResponse(
                BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ONE));

    assertThat(validator.validate(valid)).isEmpty();
    assertThat(validator.validate(invalid)).isNotEmpty();
  }

  @Test
  void protectsPublicResponseDetectionListFromMutation() {
    List<DrawingDetectionResponse> detections = new ArrayList<>();
    CreateDrawingAnalysisResponse response =
        new CreateDrawingAnalysisResponse(
            701L,
            100L,
            200L,
            "request-1",
            DrawingAnalysisType.OBJECT_DETECTION,
            DrawingAnalysisStatus.SUCCEEDED,
            new DrawingAnalysisModelResponse("yolo", "1.0"),
            detections,
            Instant.parse("2026-07-24T00:00:00Z"),
            Instant.parse("2026-07-24T00:00:01Z"));

    detections.add(
        new DrawingDetectionResponse(
            "TREE",
            new BigDecimal("0.9"),
            new BoundingBoxResponse(
                BigDecimal.ZERO, BigDecimal.ZERO, new BigDecimal("0.3"), new BigDecimal("0.4"))));

    assertThat(response.detections()).isEmpty();
  }

  private DrawingAnalysisClientCommand command(
      DrawingAnalysisActivityType activityType, DrawingAnalysisSubject drawingSubject) {
    return new DrawingAnalysisClientCommand(
        "request-1",
        701L,
        100L,
        200L,
        DrawingAnalysisScope.FINAL,
        activityType,
        drawingSubject,
        "drawings/example.png",
        "image/png",
        1200,
        800,
        "a".repeat(64));
  }
}
