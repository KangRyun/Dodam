package com.ssafy.b209.drawing.dto.request;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class SaveDrawingReflectionRequestTest {

  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

  @Test
  void copiesSelectedEmotionsToKeepRequestImmutable() {
    List<DrawingEmotionCode> emotions = new ArrayList<>(List.of(DrawingEmotionCode.HAPPY));

    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest("제목", emotions, "기뻤어", false);
    emotions.add(DrawingEmotionCode.CALM);

    assertThat(request.selectedEmotions()).containsExactly(DrawingEmotionCode.HAPPY);
  }

  @Test
  void requiresSelectedEmotionsArray() {
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest("제목", null, null, false);

    assertThat(validator.validate(request))
        .extracting(violation -> violation.getPropertyPath().toString())
        .contains("selectedEmotions");
  }

  @Test
  void rejectsTitleLongerThanDatabaseColumn() {
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest(
            "가".repeat(201), List.of(DrawingEmotionCode.HAPPY), null, false);

    assertThat(validator.validate(request))
        .extracting(violation -> violation.getPropertyPath().toString())
        .contains("title");
  }

  @Test
  void rejectsExpressionThatCanExceedUtf8mb4TextCapacity() {
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest(
            null, List.of(DrawingEmotionCode.HAPPY), "😀".repeat(16_001), false);

    assertThat(validator.validate(request))
        .extracting(violation -> violation.getPropertyPath().toString())
        .contains("expressedEmotionText");
  }
}
