package com.ssafy.b209.report.safety;

import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.HOME_GUIDE;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.SCOPE_TEXT;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.TENDENCY_TEXT;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.cardWithTendency;
import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.params.provider.Arguments.arguments;

import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

/** 2단 표현 안전 필터 — 카드 단위 검사와 로그 가드레일을 고정한다. */
class InterpretationExpressionFilterTest {

  private final InterpretationExpressionFilter filter = new InterpretationExpressionFilter();

  @Test
  void passesCardWrittenInHedgedTone() {
    ExpressionVerdict verdict = filter.inspect(cardWithTendency(TENDENCY_TEXT, 1L, 2L));

    assertThat(verdict.safe()).isTrue();
    assertThat(verdict.matchedPatterns()).isEmpty();
  }

  @Test
  void catchesUnsafeExpressionInTendencyText() {
    ExpressionVerdict verdict = filter.inspect(cardWithTendency("자존감이 낮습니다.", 1L, 2L));

    assertThat(verdict.safe()).isFalse();
    assertThat(verdict.matchedPatterns()).isNotEmpty();
  }

  /**
   * {@link InterpretationCandidate#reviewableTexts()}가 검사 대상으로 넘기는 네 필드를 각각 단독으로 오염시킨다.
   *
   * <p>필드 하나만 위험 표현을 담고 나머지 셋은 안전한 픽스처이므로, 어느 한 필드가 검사 입력에서 빠지면 그 행만 죽는다. 필드를 한 칸에 몰아 넣은 케이스로는 이
   * 구멍이 드러나지 않는다.
   */
  @ParameterizedTest(name = "{0}")
  @MethodSource("cardsWithOneUnsafeField")
  void catchesUnsafeExpressionInEveryReviewableField(
      String field, InterpretationCandidate candidate) {
    ExpressionVerdict verdict = filter.inspect(candidate);

    assertThat(verdict.safe()).withFailMessage("%s에 실린 위험 표현이 검사되지 않았습니다", field).isFalse();
    assertThat(verdict.matchedPatterns()).isNotEmpty();
    // 대조군 — 같은 자리에 안전한 문장이 들어가면 통과한다. "항상 false"인 구현을 배제한다.
    assertThat(filter.inspect(cardWithTendency(TENDENCY_TEXT, 1L, 2L)).safe()).isTrue();
  }

  private static Stream<Arguments> cardsWithOneUnsafeField() {
    return Stream.of(
        arguments(
            "title",
            cardOf(
                InterpretationCategory.EMOTION, "우울증 의심", TENDENCY_TEXT, SCOPE_TEXT, HOME_GUIDE)),
        arguments(
            "tendencyText",
            cardOf(InterpretationCategory.EMOTION, "감정 표현", "자존감이 낮습니다.", SCOPE_TEXT, HOME_GUIDE)),
        arguments(
            "scopeText",
            cardOf(
                InterpretationCategory.EMOTION,
                "감정 표현",
                TENDENCY_TEXT,
                "이 그림은 불안을 의미합니다.",
                HOME_GUIDE)),
        arguments(
            "homeObservationGuide",
            cardOf(
                InterpretationCategory.EMOTION,
                "감정 표현",
                TENDENCY_TEXT,
                SCOPE_TEXT,
                "공격적인 성향이 있어요. 가정에서 살펴봐 주세요.")));
  }

  private static InterpretationCandidate cardOf(
      InterpretationCategory category,
      String title,
      String tendencyText,
      String scopeText,
      String homeObservationGuide) {
    return new InterpretationCandidate(
        category, title, tendencyText, scopeText, homeObservationGuide, List.of(1L, 2L), null);
  }

  @Test
  void returnsPatternsNotRawText() {
    String rawText = "우리 집 이야기를 하며 자존감이 낮습니다.";

    ExpressionVerdict verdict = filter.inspect(cardWithTendency(rawText, 1L, 2L));

    assertThat(verdict.matchedPatterns()).isNotEmpty();
    // 아이 표현이 섞일 수 있으므로 원문 조각은 절대 결과에 담기지 않는다(로그 가드레일).
    assertThat(verdict.matchedPatterns())
        .allSatisfy(
            pattern -> {
              assertThat(rawText).doesNotContain(pattern);
              assertThat(InterpretationExpressionFilter.allOverinferencePatterns())
                  .contains(pattern);
            });
  }

  @Test
  void reportsEveryMatchedPatternWithoutDuplicates() {
    InterpretationCandidate multiple =
        new InterpretationCandidate(
            InterpretationCategory.EMOTION,
            "자존감이 낮습니다.",
            "자존감이 낮습니다.",
            SCOPE_TEXT,
            "애정 결핍이 느껴집니다.",
            List.of(1L, 2L),
            null);

    ExpressionVerdict verdict = filter.inspect(multiple);

    // 같은 패턴이 여러 문장에서 걸려도 한 번만 보고한다.
    assertThat(verdict.matchedPatterns()).hasSize(2).doesNotHaveDuplicates();
  }

  @Test
  void treatsBlankTextAsSafe() {
    assertThat(filter.findUnsafeExpression(null)).isEmpty();
    assertThat(filter.findUnsafeExpression("")).isEmpty();
    assertThat(filter.findUnsafeExpression("   ")).isEmpty();
  }
}
