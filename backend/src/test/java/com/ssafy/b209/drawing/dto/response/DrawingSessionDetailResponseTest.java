package com.ssafy.b209.drawing.dto.response;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class DrawingSessionDetailResponseTest {

  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void copiesSelectedEmotionsAndSerializesNullableResources() throws Exception {
    List<DrawingEmotionCode> emotions = new ArrayList<>(List.of(DrawingEmotionCode.HAPPY));
    DrawingSessionDetailResponse response =
        new DrawingSessionDetailResponse(
            10L,
            new DrawingSessionChildSummaryResponse(3L, "도담"),
            new DrawingTypeSummaryResponse(7L, "HOUSE", "집"),
            DrawingInputMethod.CANVAS,
            "우리 집",
            emotions,
            DrawingSessionStatus.IN_PROGRESS,
            DrawingStage.REFLECTION,
            null,
            null,
            null,
            null,
            Instant.parse("2026-07-23T01:00:00Z"),
            null,
            false);

    emotions.clear();

    assertThat(response.selectedEmotions()).containsExactly(DrawingEmotionCode.HAPPY);
    assertThat(objectMapper.writeValueAsString(response))
        .contains("\"latestAsset\":null", "\"latestAnalysis\":null");
  }
}
