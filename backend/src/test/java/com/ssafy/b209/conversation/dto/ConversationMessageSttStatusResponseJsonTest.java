package com.ssafy.b209.conversation.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

/** STT 상태 조회 응답 DTO의 JSON 계약(필드명·상태별 null 노출)을 검증한다. */
class ConversationMessageSttStatusResponseJsonTest {
  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void serializesSuccessResultWithSttFields() throws Exception {
    ConversationMessageSttStatusResponse response =
        new ConversationMessageSttStatusResponse(
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
            LocalDateTime.parse("2026-07-21T02:36:12"));

    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(response));

    assertThat(node.get("messageId").asLong()).isEqualTo(804L);
    assertThat(node.get("parentMessageId").asLong()).isEqualTo(803L);
    assertThat(node.get("sequence").asInt()).isEqualTo(4);
    assertThat(node.get("senderType").asText()).isEqualTo("CHILD");
    assertThat(node.get("messageType").asText()).isEqualTo("ANSWER_VOICE");
    assertThat(node.get("rawText").isNull()).isTrue();
    assertThat(node.get("sttText").asText()).isEqualTo("친구랑 같이 있어서 좋아");
    assertThat(node.get("speechStatus").asText()).isEqualTo("SUCCESS");
    assertThat(node.get("sttConfidence").asDouble()).isEqualTo(0.91d);
    assertThat(node.get("needsGuardianConfirmation").asBoolean()).isFalse();
    assertThat(node.has("createdAt")).isTrue();
  }

  @Test
  void serializesNonSuccessResultWithNullSttFields() throws Exception {
    ConversationMessageSttStatusResponse response =
        new ConversationMessageSttStatusResponse(
            804L,
            803L,
            4,
            "CHILD",
            "ANSWER_VOICE",
            null,
            null,
            "PROCESSING",
            null,
            false,
            LocalDateTime.parse("2026-07-21T02:36:12"));

    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(response));

    assertThat(node.get("speechStatus").asText()).isEqualTo("PROCESSING");
    assertThat(node.get("sttText").isNull()).isTrue();
    assertThat(node.get("sttConfidence").isNull()).isTrue();
  }
}
