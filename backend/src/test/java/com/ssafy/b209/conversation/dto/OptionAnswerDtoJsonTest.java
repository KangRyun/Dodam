package com.ssafy.b209.conversation.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;

/** 선택형 답변 요청·응답 DTO의 JSON 계약(필드명·구조)을 검증한다. */
class OptionAnswerDtoJsonTest {
  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void deserializesContractRequestExample() throws Exception {
    String json =
        """
        {
          "questionMessageId": 803,
          "selectedOptions": [
            { "optionId": "happy", "type": "EMOTION", "value": "HAPPY", "labelSnapshot": "기뻐요" }
          ],
          "directText": null
        }
        """;

    OptionAnswerRequest request = objectMapper.readValue(json, OptionAnswerRequest.class);

    assertThat(request.questionMessageId()).isEqualTo(803L);
    assertThat(request.directText()).isNull();
    assertThat(request.selectedOptions()).hasSize(1);
    SelectedOptionCommand option = request.selectedOptions().get(0);
    assertThat(option.optionId()).isEqualTo("happy");
    assertThat(option.type()).isEqualTo("EMOTION");
    assertThat(option.value()).isEqualTo("HAPPY");
    assertThat(option.labelSnapshot()).isEqualTo("기뻐요");
  }

  @Test
  void serializesResponseWithExpectedFieldNames() throws Exception {
    OptionAnswerResponse response =
        new OptionAnswerResponse(
            805L,
            800L,
            803L,
            5,
            "CHILD",
            "ANSWER_OPTION",
            List.of(new SelectedOptionCommand("happy", "EMOTION", "HAPPY", "기뻐요")),
            null,
            LocalDateTime.parse("2026-07-22T09:31:00"));

    ObjectNode node = (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(response));

    assertThat(node.get("messageId").asLong()).isEqualTo(805L);
    assertThat(node.get("conversationId").asLong()).isEqualTo(800L);
    assertThat(node.get("parentMessageId").asLong()).isEqualTo(803L);
    assertThat(node.get("sequence").asInt()).isEqualTo(5);
    assertThat(node.get("senderType").asText()).isEqualTo("CHILD");
    assertThat(node.get("messageType").asText()).isEqualTo("ANSWER_OPTION");
    assertThat(node.get("directText").isNull()).isTrue();
    assertThat(node.get("selectedOptions")).hasSize(1);
    assertThat(node.get("selectedOptions").get(0).get("optionId").asText()).isEqualTo("happy");
  }
}
