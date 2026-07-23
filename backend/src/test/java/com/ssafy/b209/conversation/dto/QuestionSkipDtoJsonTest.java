package com.ssafy.b209.conversation.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;

/** 질문 건너뛰기 요청·응답 DTO의 JSON 계약(필드명·기본값·구조)을 검증한다. */
class QuestionSkipDtoJsonTest {
  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void deserializesContractRequestExample() throws Exception {
    String json =
        """
        { "questionMessageId": 803, "reason": "CHILD_REQUEST", "returnToDrawing": true }
        """;

    QuestionSkipRequest request = objectMapper.readValue(json, QuestionSkipRequest.class);

    assertThat(request.questionMessageId()).isEqualTo(803L);
    assertThat(request.reason()).isEqualTo(SkipReason.CHILD_REQUEST);
    assertThat(request.returnToDrawing()).isTrue();
  }

  @Test
  void appliesDefaultsWhenOptionalFieldsOmitted() throws Exception {
    String json =
        """
        { "questionMessageId": 803 }
        """;

    QuestionSkipRequest request = objectMapper.readValue(json, QuestionSkipRequest.class);

    assertThat(request.questionMessageId()).isEqualTo(803L);
    assertThat(request.reason()).isEqualTo(SkipReason.CHILD_REQUEST);
    assertThat(request.returnToDrawing()).isFalse();
  }

  @Test
  void serializesResponseWithExpectedFieldNames() throws Exception {
    QuestionSkipResponse response = new QuestionSkipResponse(803L, true, 5, 10, "DRAWING");

    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(response));

    assertThat(node.get("questionMessageId").asLong()).isEqualTo(803L);
    assertThat(node.get("isSkipped").asBoolean()).isTrue();
    assertThat(node.get("questionCount").asInt()).isEqualTo(5);
    assertThat(node.get("maxQuestionCount").asInt()).isEqualTo(10);
    assertThat(node.get("currentStage").asText()).isEqualTo("DRAWING");
  }
}
