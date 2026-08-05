package com.ssafy.b209.report.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;

/** 리포트 상세 응답 DTO의 JSON 계약(필드명·구조)과 보호자 금지 필드 미포함을 검증한다. */
class ReportDetailResponseJsonTest {
  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void serializesGuardianReportStructure() throws Exception {
    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(sample()));

    assertThat(node.get("reportId").asLong()).isEqualTo(500L);
    assertThat(node.get("reportVersion").asInt()).isEqualTo(1);
    assertThat(node.get("reportStatus").asText()).isEqualTo("COMPLETED");
    assertThat(node.get("drawingSession").get("drawingTypeCode").asText())
        .isEqualTo("HOUSE_TREE_PERSON");
    assertThat(node.get("drawingSession").get("durationMs").asLong()).isEqualTo(300000L);
    assertThat(node.get("drawing").get("finalImageUrl").asText())
        .isEqualTo("https://cdn.example/final.png");
    assertThat(node.get("childExpression").get("selectedEmotions")).hasSize(1);
    assertThat(
            node.get("childExpression")
                .get("representativeUtterances")
                .get(0)
                .get("source")
                .asText())
        .isEqualTo("STT");
    assertThat(node.get("activityFacts").get("detectedObjects").get(0).asText()).isEqualTo("집");
    assertThat(node.get("activityFacts").get("pauseCount").asInt()).isEqualTo(4);
    assertThat(node.get("conversationSummary").get("questionCount").asInt()).isEqualTo(5);
    assertThat(node.get("guardianConversationGuide")).hasSize(1);
    assertThat(node.get("limitations")).hasSize(1);
    assertThat(node.get("expertReview").get("status").asText()).isEqualTo("NOT_REQUESTED");
    assertThat(node.get("expertReview").get("available").asBoolean()).isFalse();
  }

  @Test
  void carriesObservedFeaturesThatPassedReview() throws Exception {
    // 검토를 통과한 관찰 특징은 보호자 응답에 실제로 실려야 한다. 이 검증이 없으면
    //   "전부 숨겨진 채 배포"(관찰 카드가 아무에게도 도달하지 않던 상태)를 아무도 잡지 못한다.
    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(sample()));

    assertThat(node.get("observedFeatures")).hasSize(1);
    assertThat(node.get("observedFeatures").get(0).get("title").asText()).isEqualTo("집을 크게 그렸어요");
    assertThat(node.get("observedFeatures").get(0).get("description").asText())
        .isEqualTo("종이 가운데에 집을 크게 그렸어요.");
    assertThat(node.get("observedFeatures").get(0).get("evidenceSummary").asText())
        .isEqualTo("그림에서 확인했어요.");
    // 내부 코드와 노출 범위는 응답에 담지 않는다.
    assertThat(node.get("observedFeatures").get(0).has("featureCode")).isFalse();
    assertThat(node.get("observedFeatures").get(0).has("visibilityScope")).isFalse();
  }

  @Test
  void doesNotExposeGuardianForbiddenFields() throws Exception {
    String json = objectMapper.writeValueAsString(sample());
    ObjectNode node = (ObjectNode) objectMapper.readTree(json);

    assertThat(node.has("observedEmotion")).isFalse();
    assertThat(node.has("emotionConfidence")).isFalse();
    assertThat(node.has("attentionPoints")).isFalse();
    assertThat(node.has("riskScore")).isFalse();
    assertThat(node.has("visibilityScope")).isFalse();
    assertThat(json)
        .doesNotContain("observedEmotion")
        .doesNotContain("emotionConfidence")
        .doesNotContain("attentionPoints")
        .doesNotContain("riskScore")
        .doesNotContain("EXPERT_ONLY");
  }

  private ReportDetailResponse sample() {
    return new ReportDetailResponse(
        500L,
        1,
        "COMPLETED",
        new ReportDrawingSessionResponse(
            100L,
            1L,
            "HOUSE_TREE_PERSON",
            "집-나무-사람",
            "우리 가족",
            "CANVAS",
            LocalDateTime.parse("2026-07-21T02:00:00"),
            LocalDateTime.parse("2026-07-21T02:05:00"),
            300000L),
        new ReportDrawingResponse("https://cdn.example/final.png", "https://cdn.example/thumb.png"),
        new ReportChildExpressionResponse(
            List.of("HAPPY"),
            "행복한 하루였어요",
            List.of(new ReportUtteranceResponse(804L, "친구랑 있어서 좋아", "STT", false))),
        List.of(
            new ReportObservedFeatureResponse("집을 크게 그렸어요", "종이 가운데에 집을 크게 그렸어요.", "그림에서 확인했어요.")),
        new ReportActivityFactsResponse(List.of("집"), 295000L, 4, 2, true, List.of("멈춤 4회 관찰")),
        new ReportConversationSummaryResponse(5, 4, 1, "아이가 편안하게 대화했습니다"),
        List.of("오늘 그림에 대해 함께 이야기해 보세요"),
        List.of("이 리포트는 진단이 아닙니다"),
        ReportExpertReviewResponse.notRequested(),
        LocalDateTime.parse("2026-07-21T02:06:00"));
  }
}
