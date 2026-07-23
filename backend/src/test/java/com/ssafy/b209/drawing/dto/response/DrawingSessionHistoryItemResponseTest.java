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

class DrawingSessionHistoryItemResponseTest {

  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void copiesSelectedEmotionsAndSerializesNullableResources() throws Exception {
    List<DrawingEmotionCode> emotions = new ArrayList<>(List.of(DrawingEmotionCode.HAPPY));
    DrawingSessionHistoryItemResponse response =
        new DrawingSessionHistoryItemResponse(
            10L,
            null,
            new DrawingTypeSummaryResponse(7L, "HOUSE", "집"),
            null,
            DrawingInputMethod.CANVAS,
            DrawingSessionStatus.IN_PROGRESS,
            DrawingStage.DRAWING,
            emotions,
            null,
            null,
            null,
            Instant.parse("2026-07-22T04:00:00Z"),
            null);

    emotions.clear();

    assertThat(response.selectedEmotions()).containsExactly(DrawingEmotionCode.HAPPY);
    String json = objectMapper.writeValueAsString(response);
    assertThat(json)
        .contains(
            "\"thumbnailUrl\":null",
            "\"analysisStatus\":null",
            "\"reportId\":null",
            "\"reportStatus\":null",
            "\"completedAt\":null",
            "\"startedAt\":\"2026-07-22T04:00:00Z\"");
  }
}
