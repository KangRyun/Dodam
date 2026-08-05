package com.ssafy.b209.report.safety;

import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.HOME_GUIDE;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.SCOPE_TEXT;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.TENDENCY_TEXT;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.card;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.cardWithScope;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.cardWithTendency;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.childAnswer;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.items;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.selectedEmotion;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.statedEmotion;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.vision;
import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import com.ssafy.b209.report.safety.InterpretationSafetyOutcome.DemotedInterpretation;
import com.ssafy.b209.report.safety.InterpretationSafetyOutcome.ExcludedInterpretation;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;

/** 2단 검증 오케스트레이션 — 실행 순서와 실패 처리 구분을 고정한다. */
class InterpretationSafetyVerifierTest {

  private final InterpretationSafetyVerifier verifier = new InterpretationSafetyVerifier();

  @Test
  void publishesCardThatPassesBothStages() {
    InterpretationSafetyOutcome outcome =
        verifier.verify(List.of(card(1L, 2L)), items(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(outcome.published()).hasSize(1);
    assertThat(outcome.published().get(0).sourceIndex()).isZero();
    assertThat(outcome.published().get(0).independentEvidenceCount()).isEqualTo(2);
    assertThat(outcome.excluded()).isEmpty();
    assertThat(outcome.demoted()).isEmpty();
    assertThat(outcome.expertReviewRequired()).isFalse();
  }

  @Test
  void structuralGateFailureIsExclusionNotDemotion() {
    // 감정 근거만 2건 — 병합 묶음 때문에 독립 1건이라 1단에서 걸린다.
    InterpretationSafetyOutcome outcome =
        verifier.verify(
            List.of(card(1L, 2L)), items(selectedEmotion(1L, "11"), statedEmotion(2L, "202")));

    assertThat(outcome.excluded()).hasSize(1);
    assertThat(outcome.excluded().get(0).reasons())
        .containsExactly(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);

    // 부정형 — 구조 게이트 실패는 EXPERT_ONLY 강등으로 처리되지 않는다(보호자 계약 §4-3).
    assertThat(outcome.demoted()).isEmpty();
    assertThat(outcome.expertReviewRequired()).isFalse();
    assertThat(outcome.published()).isEmpty();
    // 제외 결과 타입은 노출 범위를 아예 표현하지 않는다 — 강등 결과 타입과 대비해 타입 수준에서 갈린다.
    assertThat(exposesVisibility(DemotedInterpretation.class)).isTrue();
    assertThat(exposesVisibility(ExcludedInterpretation.class)).isFalse();
  }

  private static boolean exposesVisibility(Class<?> type) {
    return Arrays.stream(type.getDeclaredMethods())
        .anyMatch(method -> method.getReturnType() == ReportFeatureVisibility.class);
  }

  @Test
  void expressionFilterFailureIsDemotionThatPreservesContent() {
    InterpretationCandidate unsafe = cardWithTendency("자존감이 낮습니다. 그런 경향이 보일 수 있습니다.", 1L, 2L);

    InterpretationSafetyOutcome outcome =
        verifier.verify(List.of(unsafe), items(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(outcome.demoted()).hasSize(1);
    DemotedInterpretation demoted = outcome.demoted().get(0);
    assertThat(demoted.visibility()).isEqualTo(ReportFeatureVisibility.EXPERT_ONLY);
    assertThat(demoted.reason()).isEqualTo(InterpretationDemotionReason.EXPRESSION_FILTER_BLOCKED);
    assertThat(outcome.expertReviewRequired()).isTrue();
    // 내용 보존 — 카드를 그대로 들고 있다.
    assertThat(demoted.candidate()).isSameAs(unsafe);
    assertThat(demoted.candidate().tendencyText()).isEqualTo("자존감이 낮습니다. 그런 경향이 보일 수 있습니다.");
    assertThat(demoted.matchedPatterns()).isNotEmpty();

    assertThat(outcome.published()).isEmpty();
    assertThat(outcome.excluded()).isEmpty();
  }

  @Test
  void demotesCardWhoseOnlyUnsafeSentenceIsScopeText() {
    // tendencyText는 가능성 어조로 안전하고 위험 표현은 scopeText에만 있다.
    // 1단은 scopeText가 비었는지만 보므로 통과하고, 강등은 2단이 그 문장을 읽었을 때만 생긴다.
    InterpretationCandidate unsafeScope = cardWithScope("이 그림은 불안을 의미합니다.", 1L, 2L);

    InterpretationSafetyOutcome outcome =
        verifier.verify(List.of(unsafeScope), items(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(outcome.demoted()).hasSize(1);
    DemotedInterpretation demoted = outcome.demoted().get(0);
    assertThat(demoted.visibility()).isEqualTo(ReportFeatureVisibility.EXPERT_ONLY);
    assertThat(demoted.reason()).isEqualTo(InterpretationDemotionReason.EXPRESSION_FILTER_BLOCKED);
    assertThat(demoted.candidate().scopeText()).isEqualTo("이 그림은 불안을 의미합니다.");
    assertThat(outcome.expertReviewRequired()).isTrue();
    // 1단은 통과했음을 못 박는다 — 제외로 끝나면 2단이 scopeText를 읽었는지 알 수 없다.
    assertThat(outcome.excluded()).isEmpty();
    assertThat(outcome.published()).isEmpty();
  }

  @Test
  void runsStructuralGateBeforeExpressionFilter() {
    // 근거도 부족하고 표현도 위험한 카드다. 1단이 먼저 돌므로 제외로 끝나고 강등 목록에는 오르지 않는다.
    InterpretationCandidate both = cardWithTendency("자존감이 낮습니다.", 1L);

    InterpretationSafetyOutcome outcome =
        verifier.verify(List.of(both), items(childAnswer(1L, "202")));

    assertThat(outcome.excluded()).hasSize(1);
    assertThat(outcome.excluded().get(0).reasons())
        .contains(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
    assertThat(outcome.demoted()).isEmpty();
    assertThat(outcome.expertReviewRequired()).isFalse();
  }

  @Test
  void failsOnlyTheProblemCardAndKeepsTheRest() {
    InterpretationCandidate healthy = card(1L, 2L);
    InterpretationCandidate weakEvidence = card(1L);
    InterpretationCandidate unsafeText =
        cardWithTendency("공격적인 성향이 있어요. 그런 모습을 보일 수 있습니다.", 1L, 2L);

    InterpretationSafetyOutcome outcome =
        verifier.verify(
            List.of(healthy, weakEvidence, unsafeText),
            items(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(outcome.published())
        .extracting(published -> published.sourceIndex())
        .containsExactly(0);
    assertThat(outcome.excluded())
        .extracting(excluded -> excluded.sourceIndex())
        .containsExactly(1);
    assertThat(outcome.demoted()).extracting(demoted -> demoted.sourceIndex()).containsExactly(2);
  }

  @Test
  void returnsEmptyCollectionsWhenNothingPassesTheGate() {
    InterpretationSafetyOutcome outcome =
        verifier.verify(
            List.of(card(1L), card(2L)), items(childAnswer(1L, "202"), vision(2L, "71")));

    // 875 계약 §10 — 통과 0건은 정상이며 예외가 아니다. 여기서는 도메인 반환값 수준으로만 고정한다.
    assertThat(outcome.published()).isEmpty();
    assertThat(outcome.excluded()).hasSize(2);
    assertThat(outcome.demoted()).isEmpty();
  }

  @Test
  void returnsEmptyCollectionsForEmptyInput() {
    InterpretationSafetyOutcome empty = verifier.verify(List.of(), List.of());
    InterpretationSafetyOutcome nulls = verifier.verify(null, null);

    assertThat(empty.published()).isEmpty();
    assertThat(empty.excluded()).isEmpty();
    assertThat(empty.demoted()).isEmpty();
    assertThat(nulls.published()).isEmpty();
    assertThat(nulls.excluded()).isEmpty();
    assertThat(nulls.demoted()).isEmpty();
  }

  @Test
  void skipsNullCandidatesWithoutFailingTheReport() {
    InterpretationSafetyOutcome outcome =
        verifier.verify(
            Arrays.asList(null, card(1L, 2L)), items(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(outcome.published()).hasSize(1);
    assertThat(outcome.published().get(0).sourceIndex()).isEqualTo(1);
  }

  @Test
  void ignoresEvidenceItemsWithoutIdentifier() {
    EvidenceCandidate withoutId =
        EvidenceCandidate.source(
            null,
            EvidenceSourceType.CHILD_ANSWER,
            "아이의 답변입니다.",
            new EvidenceSourceRef(EvidenceSourceKind.QA_ANSWER, "307"));

    InterpretationSafetyOutcome outcome =
        verifier.verify(List.of(card(1L, 2L)), items(childAnswer(1L, "202"), withoutId));

    assertThat(outcome.excluded()).hasSize(1);
    assertThat(outcome.excluded().get(0).reasons())
        .contains(InterpretationExclusionReason.EVIDENCE_REF_UNRESOLVED);
  }

  @Test
  void everyDemotedCardCarriesAStorableReasonCodeButNotThePatterns() {
    // V37: disclosure_state <> 'PUBLISHED' 면 withheld_reason_code IS NOT NULL 이다.
    // 강등에도 코드가 있어야 저장할 수 있고, 그 코드는 정규식 패턴이 아니어야 한다.
    List<InterpretationCandidate> unsafeCards =
        List.of(
            cardWithTendency("자존감이 낮습니다. 그런 경향이 보일 수 있습니다.", 1L, 2L), // 과잉 추론
            cardWithTendency("우울증이 의심됩니다. 그런 경향이 보일 수 있습니다.", 1L, 2L), // 질환명
            cardWithTendency("공격적인 성향이 있어요. 그런 경향이 보일 수 있습니다.", 1L, 2L)); // 특질 단정

    InterpretationSafetyOutcome outcome =
        verifier.verify(unsafeCards, items(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(outcome.demoted()).hasSize(3);
    for (DemotedInterpretation demoted : outcome.demoted()) {
      assertThat(demoted.reason())
          .withFailMessage("강등 결과에 저장 가능한 사유 코드가 없습니다: index=%d", demoted.sourceIndex())
          .isNotNull();
      assertThat(demoted.reason().name().length()).isLessThanOrEqualTo(40);
      // 사유 코드는 하나로 고정한다 — 정규식 38개를 분류 체계로 쪼개지 않는다.
      assertThat(demoted.reason())
          .isEqualTo(InterpretationDemotionReason.EXPRESSION_FILTER_BLOCKED);
      // 매칭 패턴은 진단용으로 남지만 사유 코드와 섞이지 않는다.
      assertThat(demoted.matchedPatterns()).isNotEmpty();
      assertThat(demoted.matchedPatterns()).doesNotContain(demoted.reason().name());
    }
    assertThat(outcome.published()).isEmpty();
    assertThat(outcome.excluded()).isEmpty();
  }

  @Test
  void keepsCardFieldsUntouchedForPublishedCards() {
    InterpretationCandidate candidate = card(1L, 2L);

    InterpretationSafetyOutcome outcome =
        verifier.verify(List.of(candidate), items(childAnswer(1L, "202"), vision(2L, "71")));

    InterpretationCandidate published = outcome.published().get(0).candidate();
    assertThat(published.category()).isEqualTo(InterpretationCategory.RELATIONSHIP);
    assertThat(published.tendencyText()).isEqualTo(TENDENCY_TEXT);
    assertThat(published.scopeText()).isEqualTo(SCOPE_TEXT);
    assertThat(published.homeObservationGuide()).isEqualTo(HOME_GUIDE);
  }
}
