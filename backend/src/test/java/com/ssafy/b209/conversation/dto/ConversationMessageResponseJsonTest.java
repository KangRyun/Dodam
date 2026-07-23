package com.ssafy.b209.conversation.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;

/** 대화 내역 조회 응답 DTO의 JSON 계약(필드명·구조·유형별 필드)을 검증한다. */
class ConversationMessageResponseJsonTest {
  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void serializesQuestionMessageWithOptionsAndTarget() throws Exception {
    ConversationMessageResponse question =
        new ConversationMessageResponse(
            803L,
            null,
            3,
            "AI",
            "QUESTION",
            "이 사람 기분은?",
            null,
            null,
            null,
            false,
            false,
            List.of(new NextQuestionOptionResponse("happy", "EMOTION", "기뻐요", "HAPPY", "🙂")),
            null,
            new NextQuestionTargetResponse(
                "PERSON", "사람", new NextQuestionBoundingBoxResponse(0.15d, 0.2d, 0.25d, 0.5d)),
            LocalDateTime.parse("2026-07-21T02:36:00"));

    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(question));

    assertThat(node.get("messageId").asLong()).isEqualTo(803L);
    assertThat(node.get("parentMessageId").isNull()).isTrue();
    assertThat(node.get("sequence").asInt()).isEqualTo(3);
    assertThat(node.get("messageType").asText()).isEqualTo("QUESTION");
    assertThat(node.get("isSkipped").asBoolean()).isFalse();
    assertThat(node.get("options")).hasSize(1);
    assertThat(node.get("options").get(0).get("optionId").asText()).isEqualTo("happy");
    assertThat(node.get("options").get(0).get("emoji").asText()).isEqualTo("🙂");
    assertThat(node.get("targetObject").get("objectCode").asText()).isEqualTo("PERSON");
    assertThat(node.get("targetObject").get("boundingBox").get("width").asDouble())
        .isEqualTo(0.25d);
    assertThat(node.get("selectedResponse").isNull()).isTrue();
  }

  @Test
  void serializesVoiceAnswerMessageWithSttFields() throws Exception {
    ConversationMessageResponse voice =
        new ConversationMessageResponse(
            804L,
            803L,
            4,
            "CHILD",
            "ANSWER_VOICE",
            null,
            "친구랑 같이 있어서 좋아",
            "SUCCESS",
            new BigDecimal("0.9100"),
            false,
            false,
            List.of(),
            null,
            null,
            LocalDateTime.parse("2026-07-21T02:36:12"));

    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(voice));

    assertThat(node.get("messageType").asText()).isEqualTo("ANSWER_VOICE");
    assertThat(node.get("sttText").asText()).isEqualTo("친구랑 같이 있어서 좋아");
    assertThat(node.get("speechStatus").asText()).isEqualTo("SUCCESS");
    assertThat(node.get("sttConfidence").asDouble()).isEqualTo(0.91d);
    assertThat(node.get("options")).isEmpty();
    assertThat(node.get("targetObject").isNull()).isTrue();
  }

  @Test
  void serializesPageMetadata() throws Exception {
    ConversationMessagePageResponse page =
        new ConversationMessagePageResponse(List.of(), 0, 50, 12L, 1, true, true, false);

    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(page));

    assertThat(node.get("content")).isEmpty();
    assertThat(node.get("page").asInt()).isZero();
    assertThat(node.get("size").asInt()).isEqualTo(50);
    assertThat(node.get("totalElements").asLong()).isEqualTo(12L);
    assertThat(node.get("hasNext").asBoolean()).isFalse();
  }
}
