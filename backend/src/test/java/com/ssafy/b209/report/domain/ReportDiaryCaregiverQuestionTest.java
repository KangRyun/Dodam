package com.ssafy.b209.report.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import org.junit.jupiter.api.Test;

/** "오늘 마음 나누기" 교감 카드 Entity가 유형·공감 반응·함께 해보기를 그대로 보존하는지 검증한다. */
class ReportDiaryCaregiverQuestionTest {

  private final Report report = mock(Report.class);

  @Test
  void keepsConnectionTypeAndResponseGuideAndCoRegulationAction() {
    ReportDiaryCaregiverQuestion card =
        ReportDiaryCaregiverQuestion.create(
            report,
            "그때 네 마음은 어땠어?",
            "그때 감정을 아이 말로 더 들어보기",
            "FEELING_SHARING",
            "\"그랬구나, 그런 마음이었구나\" 하고 마음을 그대로 받아 주세요.",
            "그때 마음을 색이나 표정으로 같이 그려 볼까요?",
            0);

    assertThat(card.getConnectionType()).isEqualTo("FEELING_SHARING");
    assertThat(card.getResponseGuide()).contains("마음을 그대로 받아 주세요");
    assertThat(card.getCoRegulationAction()).contains("같이 그려 볼까요");
    assertThat(card.getDisplayOrder()).isZero();
  }

  @Test
  void allowsNullResponseGuideAndCoRegulationActionForGeneralConnection() {
    ReportDiaryCaregiverQuestion card =
        ReportDiaryCaregiverQuestion.create(
            report, "오늘 그림에서 가장 마음에 남는 부분이 어디야?", null, "GENERAL_CONNECTION", null, null, 0);

    assertThat(card.getConnectionType()).isEqualTo("GENERAL_CONNECTION");
    assertThat(card.getResponseGuide()).isNull();
    assertThat(card.getCoRegulationAction()).isNull();
  }

  @Test
  void rejectsNullConnectionTypeSoTheNotNullColumnIsNeverViolatedFromCode() {
    assertThatThrownBy(
            () ->
                ReportDiaryCaregiverQuestion.create(
                    report, "그때 마음이 어땠어?", null, null, "반응 안내", null, 0))
        .isInstanceOf(NullPointerException.class)
        .hasMessageContaining("connectionType");
  }
}
