package com.ssafy.b209.report.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DiaryCaregiverQuestionDraft;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryCaregiverQuestionResponse;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * "오늘 마음 나누기" 교감 카드의 JSON 계약을 검증한다. AI 응답(camelCase) 수용과 보호자 응답 직렬화(camelCase) 양쪽 모두 신규 3필드
 * (connectionType·responseGuide·coRegulationAction)를 다뤄야 한다.
 */
class ReportDiaryCaregiverQuestionJsonTest {
  private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

  @Test
  void ingestsConnectionFieldsFromAiCamelCaseResponse() throws Exception {
    String aiJson =
        """
        {
          "question": "그때 네 마음은 어땠어?",
          "purpose": "그때 감정을 아이 말로 더 들어보기",
          "connectionType": "FEELING_SHARING",
          "responseGuide": "마음을 그대로 받아 주세요.",
          "coRegulationAction": "같이 그려 볼까요?",
          "evidenceRefs": [{"kind": "QA_ANSWER", "id": "101"}]
        }
        """;

    DiaryCaregiverQuestionDraft draft =
        objectMapper.readValue(aiJson, DiaryCaregiverQuestionDraft.class);

    assertThat(draft.connectionType()).isEqualTo("FEELING_SHARING");
    assertThat(draft.responseGuide()).isEqualTo("마음을 그대로 받아 주세요.");
    assertThat(draft.coRegulationAction()).isEqualTo("같이 그려 볼까요?");
    assertThat(draft.evidenceRefs()).hasSize(1);
  }

  @Test
  void serializesConnectionFieldsAsCamelCaseForGuardianApp() throws Exception {
    DiaryCaregiverQuestionResponse response =
        new DiaryCaregiverQuestionResponse(
            "그때 네 마음은 어땠어?",
            "그때 감정을 아이 말로 더 들어보기",
            "COMFORT_SEEKING",
            "\"많이 속상했겠다\" 하고 알아주세요.",
            "어떻게 말하면 좋을지 같이 정해 볼까요?",
            List.of());

    ObjectNode node =
        (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(response));

    assertThat(node.get("connectionType").asText()).isEqualTo("COMFORT_SEEKING");
    assertThat(node.get("responseGuide").asText()).contains("많이 속상했겠다");
    assertThat(node.get("coRegulationAction").asText()).contains("같이 정해 볼까요");
    assertThat(node.get("evidenceRefs").isArray()).isTrue();
  }

  @Test
  void keepsNullConnectionGuideFieldsForGeneralConnectionCard() throws Exception {
    DiaryCaregiverQuestionResponse response =
        new DiaryCaregiverQuestionResponse(
            "오늘 그림에서 가장 마음에 남는 부분이 어디야?", null, "GENERAL_CONNECTION", null, null, List.of());

    ObjectNode node =
        (ObjectNode) objectMapper.readTree(objectMapper.writeValueAsString(response));

    assertThat(node.get("connectionType").asText()).isEqualTo("GENERAL_CONNECTION");
    assertThat(node.get("coRegulationAction").isNull()).isTrue();
  }
}
