package com.ssafy.b209.drawing.dto.request;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.response.CreateDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeSummaryResponse;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.time.Instant;
import java.time.OffsetDateTime;
import org.junit.jupiter.api.Test;

class CreateDrawingSessionRequestTest {

  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();
  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void rejectsNullAndNonPositiveRequiredRequestFields() {
    CreateDrawingSessionRequest request =
        new CreateDrawingSessionRequest(
            0L, null, null, null, new CanvasConfigurationRequest(-1, -1, ""));

    assertThat(validator.validate(request))
        .extracting(violation -> violation.getPropertyPath().toString())
        .containsExactlyInAnyOrder("childId", "drawingTypeId", "inputMethod", "clientStartedAt");
  }

  @Test
  void rejectsNegativeIdentifiers() {
    CreateDrawingSessionRequest request =
        new CreateDrawingSessionRequest(
            -1L,
            -2L,
            DrawingInputMethod.CANVAS,
            OffsetDateTime.parse("2026-07-21T12:34:56+09:00"),
            null);

    assertThat(validator.validate(request))
        .extracting(violation -> violation.getPropertyPath().toString())
        .containsExactlyInAnyOrder("childId", "drawingTypeId");
  }

  @Test
  void doesNotCascadeValidationToCanvasConfiguration() {
    CreateDrawingSessionRequest request =
        new CreateDrawingSessionRequest(
            1L,
            2L,
            DrawingInputMethod.CANVAS,
            OffsetDateTime.parse("2026-07-21T12:34:56+09:00"),
            new CanvasConfigurationRequest(null, null, null));

    assertThat(validator.validate(request)).isEmpty();
  }

  @Test
  void serializesAndDeserializesRequestEnumsAndClientTime() throws Exception {
    String json =
        """
        {
          "childId": 1,
          "drawingTypeId": 2,
          "inputMethod": "UPLOAD",
          "clientStartedAt": "2026-07-21T12:34:56+09:00",
          "canvas": {"width": 1024, "height": 768, "backgroundColor": "#FFFFFF"}
        }
        """;

    CreateDrawingSessionRequest request =
        objectMapper.readValue(json, CreateDrawingSessionRequest.class);
    JsonNode serialized = objectMapper.readTree(objectMapper.writeValueAsString(request));

    assertThat(request.inputMethod()).isEqualTo(DrawingInputMethod.UPLOAD);
    assertThat(request.clientStartedAt())
        .isEqualTo(OffsetDateTime.parse("2026-07-21T12:34:56+09:00"));
    assertThat(serialized.get("inputMethod").asText()).isEqualTo("UPLOAD");
    assertThat(OffsetDateTime.parse(serialized.get("clientStartedAt").asText()).toInstant())
        .isEqualTo(request.clientStartedAt().toInstant());
  }

  @Test
  void serializesResponseOnlyWithContractFields() throws Exception {
    CreateDrawingSessionResponse response =
        new CreateDrawingSessionResponse(
            10L,
            1L,
            new DrawingTypeSummaryResponse(2L, "HOUSE", "House"),
            DrawingInputMethod.CANVAS,
            DrawingSessionStatus.IN_PROGRESS,
            DrawingStage.DRAWING,
            true,
            Instant.parse("2026-07-21T03:34:56Z"));

    JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(response));

    assertThat(json.fieldNames())
        .toIterable()
        .containsExactly(
            "drawingSessionId",
            "childId",
            "drawingType",
            "inputMethod",
            "sessionStatus",
            "currentStage",
            "tutorialRequired",
            "startedAt");
    assertThat(json.get("inputMethod").asText()).isEqualTo("CANVAS");
    assertThat(json.get("sessionStatus").asText()).isEqualTo("IN_PROGRESS");
    assertThat(json.get("currentStage").asText()).isEqualTo("DRAWING");
    assertThat(json.get("startedAt").asText()).isEqualTo("2026-07-21T03:34:56Z");
  }
}
