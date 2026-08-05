package com.ssafy.b209.report.safety;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.assertj.core.api.SoftAssertions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 2단 표현 안전 필터가 AI 측 {@code ai/report_safety.py}와 <strong>같은 문장 집합에 같은 판정</strong>을 내리는지 고정한다.
 *
 * <p>문장은 {@code ai/test_report_safety.py}의 경계 문장을 그대로 가져왔고, 기대값은 2026-08-05에 그 모듈을 직접 실행해 얻은
 * 판정이다(Python 3.12, 13개 테스트 통과). 기준이 갈리면 통과·차단이 엇갈리므로(보호자 계약 §4-3) 이 표가 회귀 방어선이다.
 *
 * <p>기대값을 구현 산출값에서 역산하지 않았다. AI 모듈의 실제 출력이 기대값이며, 갈리는 문장이 나오면 BE 패턴을 고치는 것이 아니라 어느 쪽이 정답인지 확정해야 한다.
 *
 * <p><strong>가능성 어조 표지 축은 여기 없다.</strong> AI에서 그 검사는 이 모듈이 아니라 조립 계층({@code ai/report_client.py}의
 * {@code _TENTATIVE_MARKERS})에 있고, BE에서도 2단이 아니라 1단 게이트가 한다. 그래서 어조 정합은 {@link
 * InterpretationPublicationGateAiParityTest}가 고정한다 — 코드가 있는 곳에 테스트를 둔다.
 */
class InterpretationExpressionFilterAiParityTest {

  private final InterpretationExpressionFilter filter = new InterpretationExpressionFilter();

  /**
   * AI 코퍼스 한 줄이다.
   *
   * @param text 검사 문장
   * @param definitive AI {@code has_definitive_diagnosis} 기대값
   * @param overinference AI {@code has_overinference} 기대값
   */
  private record ParityCase(String text, boolean definitive, boolean overinference) {}

  /** {@code BlocksDefinitiveDiagnosisTest.DEFINITIVE} — 단정적 진단은 차단. */
  private static final List<ParityCase> DEFINITIVE =
      List.of(
          new ParityCase("우울증이 의심되는 그림입니다.", true, false),
          new ParityCase("불안장애로 진단됩니다.", true, false),
          new ParityCase("이 아이는 ADHD입니다.", true, false),
          new ParityCase("주의력 결핍 장애가 있습니다.", true, false),
          new ParityCase("자폐 스펙트럼 경향이 뚜렷합니다.", true, false),
          new ParityCase("틱 장애로 진단이 필요합니다.", true, false),
          new ParityCase("이 그림은 공격성을 나타냅니다.", true, false),
          new ParityCase("이 아이는 정서적으로 불안정합니다.", true, false),
          new ParityCase("분명히 정서 불안 문제가 있습니다.", true, false),
          new ParityCase("틀림없이 우울 성향이 강합니다.", true, false));

  /** {@code AllowsHedgedConcernTest.HEDGED} — 경향성 우려 소견은 통과. */
  private static final List<ParityCase> HEDGED =
      List.of(
          new ParityCase("불안한 마음이 들 수 있어요.", false, false),
          new ParityCase("속상한 마음이 담긴 듯한 그림이에요.", false, false),
          new ParityCase("외로움을 느끼는 경향이 보일 수 있어요.", false, false),
          new ParityCase("정서적으로 조금 위축된 듯 보여요.", false, false),
          new ParityCase("그럴 수 있어요, 조심스럽게 살펴보면 좋겠어요.", false, false),
          new ParityCase("집을 크게 그린 점이 인상적이에요.", false, false),
          new ParityCase("가족을 함께 그린 것이 따뜻하게 느껴져요.", false, false));

  /** {@code BlocksOverinferenceTest.OVERINFERENCE} — 고정 특질 규정은 차단. */
  private static final List<ParityCase> OVERINFERENCE =
      List.of(
          new ParityCase("이 아이는 소심합니다.", false, true),
          new ParityCase("성격이 내성적이에요.", false, true),
          new ParityCase("공격적인 성향이 있어요.", false, true),
          new ParityCase("예민한 기질입니다.", false, true),
          new ParityCase("정서적으로 불안한 아이입니다.", false, true),
          new ParityCase("소심한 아이예요.", false, true),
          new ParityCase("자존감이 낮습니다.", false, true),
          new ParityCase("공감 능력이 부족해요.", false, true),
          new ParityCase("애정 결핍이 느껴집니다.", false, true));

  /** {@code AllowsObservationTest.SAFE} — 행동 관찰·여지 표현은 통과. */
  private static final List<ParityCase> SAFE =
      List.of(
          new ParityCase("소심한 편일 수 있어요.", false, false),
          new ParityCase("내성적인 경향이 보여요.", false, false),
          new ParityCase("조금 산만해 보였어요.", false, false),
          new ParityCase("조심스러운 모습을 보였어요.", false, false),
          new ParityCase("밝고 활발한 모습이 인상적이에요.", false, false),
          new ParityCase("외로움을 느끼는 경향이 보일 수 있어요.", false, false),
          new ParityCase("자신감 있게 색을 칠했어요.", false, false),
          new ParityCase("가족을 함께 그린 점이 따뜻하게 느껴져요.", false, false));

  @Test
  @DisplayName("AI 코퍼스 전체에 대해 진단 단정·과잉 추론 판정이 AI와 일치한다")
  void matchesAiVerdictsForEverySentence() {
    SoftAssertions softly = new SoftAssertions();
    for (List<ParityCase> group : List.of(DEFINITIVE, HEDGED, OVERINFERENCE, SAFE)) {
      for (ParityCase parityCase : group) {
        softly
            .assertThat(!filter.findDefinitiveDiagnosis(parityCase.text()).isEmpty())
            .withFailMessage(
                "진단 단정 판정이 AI와 갈립니다. 기대=%s 문장=%s", parityCase.definitive(), parityCase.text())
            .isEqualTo(parityCase.definitive());
        softly
            .assertThat(!filter.findOverinference(parityCase.text()).isEmpty())
            .withFailMessage(
                "과잉 추론 판정이 AI와 갈립니다. 기대=%s 문장=%s", parityCase.overinference(), parityCase.text())
            .isEqualTo(parityCase.overinference());
      }
    }
    softly.assertAll();
  }

  @Test
  @DisplayName("AI 결합 판정(has_unsafe_expression)과도 일치한다")
  void matchesAiCombinedVerdict() {
    assertThat(filter.hasUnsafeExpression("우울증입니다.")).isTrue();
    assertThat(filter.hasUnsafeExpression("공격적인 성향이 있어요.")).isTrue();
    assertThat(filter.hasUnsafeExpression("즐거워 보여요.", "소심한 편일 수 있어요.")).isFalse();
    assertThat(filter.hasUnsafeExpression("괜찮은 그림이에요.", "자존감이 낮습니다.")).isTrue();
    assertThat(filter.hasUnsafeExpression("괜찮아요.", "즐거워 보여요.")).isFalse();
  }

  @Test
  @DisplayName("코퍼스가 AI 테스트 파일과 같은 규모다")
  void coversTheWholeAiCorpus() {
    // 문장 수가 줄면 회귀 방어선이 조용히 약해진다. AI 테스트 파일의 목록 크기를 못박는다.
    assertThat(DEFINITIVE).hasSize(10);
    assertThat(HEDGED).hasSize(7);
    assertThat(OVERINFERENCE).hasSize(9);
    assertThat(SAFE).hasSize(8);
  }

  @Test
  @DisplayName("패턴 개수가 AI 모듈과 같다")
  void portsEveryAiPattern() {
    // ai/report_safety.py: _DISORDER_TERMS 28 + _ASSERTION_PATTERNS 5 = _ALL_PATTERNS 33,
    // _OVERINFERENCE_PATTERNS 5.
    assertThat(InterpretationExpressionFilter.allDefinitivePatterns()).hasSize(33);
    assertThat(InterpretationExpressionFilter.allOverinferencePatterns()).hasSize(5);
  }
}
