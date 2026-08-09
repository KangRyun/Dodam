package com.ssafy.b209.report.safety;

import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.activityMetric;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.answerRef;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.card;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.childAnswer;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.items;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.longitudinal;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.pool;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.ref;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.repeatedSubject;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.selectedEmotion;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.statedEmotion;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.vision;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.entry;

import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import java.util.Arrays;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.assertj.core.api.SoftAssertions;
import org.junit.jupiter.api.Test;

/**
 * 1단 구조적 공개 게이트가 AI 쪽 같은 게이트({@code ai/interpretation_gate.py})와 <strong>같은 판정</strong>을 내는지 고정한다.
 *
 * <p>두 구현이 같은 계약(§4-1)을 서로 다른 계층에서 집행한다. 하나가 통과시키고 다른 하나가 막으면 그 차이는 배포 후에야 "경향 카드가 안 보인다"로 드러난다.
 * 그래서 <strong>코퍼스 통과만 보지 않고 규칙 자체</strong>(임계값·병합 묶음·아이 표현 축)까지 대조한다.
 *
 * <p><strong>번역할 수 없는 축이 하나 있다.</strong> AI는 배제 대상 참조를 외부 집합({@code blocked_refs})으로 주입받지만 BE는 근거
 * 항목의 필드({@code sttNeedsConfirmation}·{@code crisisReason})에서 읽는다. 그래서 아래 배제 케이스는 "그 원본을 신고한 근거 항목이
 * 풀에 있고 그 항목에 표시가 붙어 있다"로 옮겼다. 원본이 근거 항목으로 실려 있지 않으면 BE는 배제 여부를 알 수 없다 — 그 원본을 근거로 쓰려면 항목이 있어야 하므로
 * 실전 경로에서는 문제가 되지 않지만, 두 구현이 같은 입력을 받는 것은 아니다.
 */
class InterpretationPublicationGateAiParityTest {

  private final InterpretationPublicationGate gate = new InterpretationPublicationGate();

  // ── 규칙 자체 대조 ────────────────────────────────────────────────

  @Test
  void sharesTheSameThresholdAndFamilyRulesWithAi() {
    SoftAssertions softly = new SoftAssertions();

    // MIN_INDEPENDENT_EVIDENCE = 2
    softly
        .assertThat(IndependentEvidenceCounter.MINIMUM_INDEPENDENT_EVIDENCE)
        .as("최소 독립 근거 수")
        .isEqualTo(2);

    // CHILD_EXPRESSION_SOURCE_TYPES = {"CHILD_ANSWER", "SELECTED_EMOTION", "STATED_EMOTION"}
    softly
        .assertThat(
            EnumSet.allOf(EvidenceSourceType.class).stream()
                .filter(EvidenceSourceType::isChildExpression)
                .toList())
        .as("아이 표현 근거 종류")
        .containsExactlyInAnyOrder(
            EvidenceSourceType.CHILD_ANSWER,
            EvidenceSourceType.SELECTED_EMOTION,
            EvidenceSourceType.STATED_EMOTION);

    // CHILD_EXPRESSION_REF_KINDS = {"QA_ANSWER", "EMOTION_SELECTION"}
    softly
        .assertThat(
            EnumSet.allOf(EvidenceSourceKind.class).stream()
                .filter(EvidenceSourceKind::isChildExpression)
                .toList())
        .as("아이 표현 원본 종류")
        .containsExactlyInAnyOrder(
            EvidenceSourceKind.QA_ANSWER, EvidenceSourceKind.EMOTION_SELECTION);

    // _MERGED_FAMILIES = ({"SELECTED_EMOTION", "STATED_EMOTION"}, {"ACTIVITY_METRIC"})
    Map<EvidenceSourceType, EvidenceMergeFamily> families = new EnumMap<>(EvidenceSourceType.class);
    for (EvidenceSourceType type : EvidenceSourceType.values()) {
      if (type.mergeFamily() != null) {
        families.put(type, type.mergeFamily());
      }
    }
    softly
        .assertThat(families)
        .as("병합 묶음")
        .containsOnly(
            entry(EvidenceSourceType.SELECTED_EMOTION, EvidenceMergeFamily.EMOTION),
            entry(EvidenceSourceType.STATED_EMOTION, EvidenceMergeFamily.EMOTION),
            entry(EvidenceSourceType.ACTIVITY_METRIC, EvidenceMergeFamily.ACTIVITY_METRIC));

    softly.assertAll();
  }

  @Test
  void sharesTheSameTentativeToneMarkersWithAi() {
    // ai/report_client.py:615 _TENTATIVE_MARKERS = ("수 있", "보입니다", "보여요", "경향", "듯", "가능성")
    // 같은 어조 규칙을 두 곳에서 집행한다. BE가 넓으면 AI가 버린 문장을 BE만 통과시킨다.
    assertThat(InterpretationPublicationGate.possibilityToneMarkers())
        .containsExactly("수 있", "보입니다", "보여요", "경향", "듯", "가능성");
  }

  @Test
  void agreesWithAiOnToneMarkerBoundarySentences() {
    // AI는 부분 문자열 포함으로 검사한다: any(marker in tendency for marker in _TENTATIVE_MARKERS)
    Map<String, Boolean> aiVerdict = new LinkedHashMap<>();
    aiVerdict.put("가족에게 의지하려는 경향이 보일 수 있습니다.", true); // 경향 · 수 있
    aiVerdict.put("혼자 있는 시간을 편하게 느끼는 듯합니다.", true); // 듯
    aiVerdict.put("관심을 표현하려는 가능성이 있습니다.", true); // 가능성
    aiVerdict.put("새로운 상황을 조심스럽게 살피는 것으로 보입니다.", true); // 보입니다
    aiVerdict.put("친구와 함께 있는 상황을 즐거워해 보여요.", true); // 보여요
    aiVerdict.put("이야기를 나눌 때 보호자를 자주 확인하는 모습을 보였어요.", false); // 모습·보였어요는 표지가 아니다
    aiVerdict.put("친구와 함께 있는 상황을 즐거워하는 것 같아요.", false); // 것 같은 표지가 아니다
    aiVerdict.put("혼자 있는 시간을 편하게 느낄지도 모릅니다.", false); // 일지도는 표지가 아니다
    aiVerdict.put("보호자를 자주 확인하는 모습이 보이는 활동이었어요.", false); // 보이는은 표지가 아니다
    aiVerdict.put("가족에게 의지하려는 경우가 있을수있습니다.", false); // 공백 없는 "수있"은 표지가 아니다
    aiVerdict.put("가족에게 정서적으로 의지합니다.", false); // 단정
    aiVerdict.put("친구와 잘 어울린다.", false); // 단정

    SoftAssertions softly = new SoftAssertions();
    aiVerdict.forEach(
        (sentence, expected) ->
            softly
                .assertThat(InterpretationPublicationGate.hasPossibilityTone(sentence))
                .as("어조 표지 판정이 AI와 갈립니다: %s", sentence)
                .isEqualTo(expected));
    softly.assertAll();

    // 코퍼스가 조용히 줄어드는 것을 막는다.
    assertThat(aiVerdict).hasSize(12);
    assertThat(aiVerdict.values().stream().filter(Boolean::booleanValue).count()).isEqualTo(5);
  }

  @Test
  void sharesTheSameEnumValueSetsWithAiWhitelists() {
    SoftAssertions softly = new SoftAssertions();

    // ai/report_client.py _EVIDENCE_SOURCE_TYPES
    softly
        .assertThat(EvidenceSourceType.values())
        .extracting(Enum::name)
        .as("근거 종류 값 집합")
        .containsExactlyInAnyOrder(
            "VISION",
            "CHILD_ANSWER",
            "SELECTED_EMOTION",
            "STATED_EMOTION",
            "ACTIVITY_METRIC",
            "REPEATED_SUBJECT",
            "LONGITUDINAL");

    // ai/report_client.py _EVIDENCE_REF_KINDS
    softly
        .assertThat(EvidenceSourceKind.values())
        .extracting(Enum::name)
        .as("원본 종류 값 집합")
        .containsExactlyInAnyOrder(
            "QA_ANSWER",
            "DETECTED_OBJECT",
            "VLM_OBSERVATION",
            "EMOTION_SELECTION",
            "ACTIVITY_METRIC",
            "PRIOR_ACTIVITY");

    // ai/report_client.py _INTERPRETATION_CATEGORIES
    softly
        .assertThat(InterpretationCategory.values())
        .extracting(Enum::name)
        .as("관찰 관점 라벨 값 집합")
        .containsExactlyInAnyOrder(
            "RELATIONSHIP", "EMOTION", "SELF_EXPRESSION", "ACTIVITY_STYLE", "ADAPTATION");

    softly.assertAll();
  }

  // ── IndependentCountTest ─────────────────────────────────────────

  @Test
  void twoDifferentOriginsPass() {
    // AI: test_two_different_origins_pass — passed=True, independent_count=2
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L, 2L), pool(childAnswer(1L, "202"), childAnswer(2L, "318")));

    assertThat(decision.passed()).isTrue();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
  }

  @Test
  void sameOriginCountsOnce() {
    // AI: test_same_origin_counts_once — count=1, reason=NOT_ENOUGH_INDEPENDENT_EVIDENCE
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L, 2L), pool(childAnswer(1L, "202"), childAnswer(2L, "202")));

    assertThat(decision.passed()).isFalse();
    assertThat(decision.independentEvidenceCount()).isEqualTo(1);
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void singleEvidenceFails() {
    // AI: test_single_evidence_fails
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L), pool(childAnswer(1L, "202")));

    assertThat(decision.passed()).isFalse();
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void noReferenceFails() {
    // AI: test_no_reference_fails — reason=NO_EVIDENCE. BE는 EVIDENCE_REF_MISSING 코드로 같은 판정을 낸다.
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(), pool(childAnswer(1L, "202")));

    assertThat(decision.passed()).isFalse();
    assertThat(decision.reasons()).contains(InterpretationExclusionReason.EVIDENCE_REF_MISSING);
  }

  @Test
  void unknownReferenceDoesNotPadTheCount() {
    // AI: test_unknown_reference_does_not_pad_the_count — count=1(유효한 1건만)
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L, 99L), pool(childAnswer(1L, "202")));

    assertThat(decision.passed()).isFalse();
    assertThat(decision.independentEvidenceCount()).isEqualTo(1);
    // AI는 미존재 참조를 조용히 건너뛰고 NOT_ENOUGH만 남긴다. BE는 사유를 하나 더 남긴다 — 판정은 같다.
    assertThat(decision.reasons())
        .contains(
            InterpretationExclusionReason.EVIDENCE_REF_UNRESOLVED,
            InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void derivedEvidenceAndItsOriginCountOnce() {
    // AI: test_derived_and_its_origin_count_once — count=2(3이 아니다)
    Map<Long, EvidenceCandidate> pool =
        pool(
            repeatedSubject(1L, answerRef("202"), answerRef("318")),
            childAnswer(2L, "202")); // 파생의 원본 중 하나

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.passed()).isTrue();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
  }

  @Test
  void derivedAloneCanPassWithTwoOrigins() {
    // AI: test_derived_alone_can_pass_with_two_origins
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L), pool(repeatedSubject(1L, answerRef("202"), answerRef("318"))));

    assertThat(decision.passed()).isTrue();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
  }

  // ── MergeFamilyTest ──────────────────────────────────────────────

  @Test
  void emotionFamilyMergesToOne() {
    // AI: test_emotion_family_merges_to_one — count=1, NOT_ENOUGH
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L, 2L), pool(selectedEmotion(1L, "5"), statedEmotion(2L, "202")));

    assertThat(decision.passed()).isFalse();
    assertThat(decision.independentEvidenceCount()).isEqualTo(1);
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void emotionPlusOtherOriginPasses() {
    // AI: test_emotion_plus_other_origin_passes
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L, 2L), pool(selectedEmotion(1L, "5"), childAnswer(2L, "202")));

    assertThat(decision.passed()).isTrue();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
  }

  @Test
  void activityMetricsMergeToOne() {
    // AI: test_activity_metrics_merge_to_one — count=1
    Map<Long, EvidenceCandidate> pool =
        pool(activityMetric(1L, "m1"), activityMetric(2L, "m2"), activityMetric(3L, "m3"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L, 3L), pool);

    assertThat(decision.passed()).isFalse();
    assertThat(decision.independentEvidenceCount()).isEqualTo(1);
  }

  // ── ChildExpressionRequiredTest ──────────────────────────────────

  @Test
  void visionAndMetricOnlyIsBlocked() {
    // AI: test_vision_and_metric_only_is_blocked — NO_CHILD_EXPRESSION, count=2
    Map<Long, EvidenceCandidate> pool = pool(vision(1L, "d1"), activityMetric(2L, "m1"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.passed()).isFalse();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.CHILD_EXPRESSION_EVIDENCE_MISSING);
  }

  @Test
  void visionPlusChildAnswerPasses() {
    // AI: test_vision_plus_child_answer_passes
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L, 2L), pool(vision(1L, "d1"), childAnswer(2L, "202")));

    assertThat(decision.passed()).isTrue();
  }

  @Test
  void derivedFromChildOriginCountsAsChildExpression() {
    // AI: test_derived_from_child_origin_counts_as_child_expression — 말단 kind로 충족한다
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L), pool(repeatedSubject(1L, answerRef("202"), answerRef("318"))));

    assertThat(decision.passed()).isTrue();
    assertThat(decision.reasons())
        .doesNotContain(InterpretationExclusionReason.CHILD_EXPRESSION_EVIDENCE_MISSING);
  }

  @Test
  void derivedFromVisionOnlyIsNotChildExpression() {
    // AI: test_derived_from_vision_only_is_not_child_expression — NO_CHILD_EXPRESSION
    Map<Long, EvidenceCandidate> pool =
        pool(
            longitudinal(
                1L,
                ref(EvidenceSourceKind.DETECTED_OBJECT, "d1"),
                ref(EvidenceSourceKind.VLM_OBSERVATION, "v1")));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L), pool);

    assertThat(decision.passed()).isFalse();
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.CHILD_EXPRESSION_EVIDENCE_MISSING);
  }

  // ── BlockedEvidenceTest ──────────────────────────────────────────

  @Test
  void blockedOriginFailsBeforeCounting() {
    // AI: test_blocked_origin_fails_before_counting — BLOCKED_EVIDENCE
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), blocked(2L, "318"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.passed()).isFalse();
    assertThat(decision.reasons()).contains(InterpretationExclusionReason.EVIDENCE_STT_UNCONFIRMED);
  }

  @Test
  void blockedOriginInsideDerivedEvidenceAlsoFails() {
    // AI: test_blocked_origin_inside_derived_evidence_also_fails
    Map<Long, EvidenceCandidate> pool =
        pool(repeatedSubject(1L, answerRef("202"), answerRef("318")), blocked(2L, "318"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L), pool);

    // 카드는 파생 근거만 참조했지만, 그 파생이 펼쳐지며 배제 대상 원본에 닿는다.
    assertThat(decision.passed()).isFalse();
    assertThat(decision.reasons()).contains(InterpretationExclusionReason.EVIDENCE_STT_UNCONFIRMED);
  }

  @Test
  void unrelatedBlockDoesNotAffect() {
    // AI: test_unrelated_block_does_not_affect — 무관한 배제는 판정을 바꾸지 않는다
    Map<Long, EvidenceCandidate> pool =
        pool(childAnswer(1L, "202"), childAnswer(2L, "318"), blocked(3L, "999"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.passed()).isTrue();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
  }

  // ── ApplyTest ────────────────────────────────────────────────────

  @Test
  void onlyFailingCardIsRemoved() {
    // AI: test_only_failing_card_is_removed
    InterpretationCandidate good = card(1L, 2L);
    InterpretationCandidate bad = card(1L);

    InterpretationSafetyOutcome outcome =
        new InterpretationSafetyVerifier()
            .verify(List.of(good, bad), items(childAnswer(1L, "202"), childAnswer(2L, "318")));

    assertThat(outcome.published())
        .extracting(published -> published.candidate())
        .containsExactly(good);
    assertThat(outcome.excluded())
        .extracting(excluded -> excluded.candidate())
        .containsExactly(bad);
    assertThat(outcome.excluded().get(0).reasons())
        .containsExactly(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void allFailingYieldsEmptyList() {
    // AI: test_all_failing_yields_empty_list — 통과 0건은 정상이다(875 §10)
    InterpretationSafetyOutcome outcome =
        new InterpretationSafetyVerifier().verify(List.of(card(1L)), items(childAnswer(1L, "202")));

    assertThat(outcome.published()).isEmpty();
    assertThat(outcome.excluded()).hasSize(1);
  }

  @Test
  void noCardsIsFine() {
    // AI: test_no_cards_is_fine
    InterpretationSafetyOutcome outcome =
        new InterpretationSafetyVerifier().verify(List.of(), List.of());

    assertThat(outcome.published()).isEmpty();
    assertThat(outcome.excluded()).isEmpty();
    assertThat(outcome.demoted()).isEmpty();
  }

  // ── GateIsNotADowngradeTest ──────────────────────────────────────

  @Test
  void gateDecisionCarriesNoVisibilityScope() {
    // AI: test_gate_result_carries_no_visibility_scope — 구조 게이트는 노출 범위를 다루지 않는다
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L), pool(childAnswer(1L, "202")));

    assertThat(
            Arrays.stream(InterpretationPublicationGate.Decision.class.getDeclaredMethods())
                .anyMatch(method -> method.getReturnType() == ReportFeatureVisibility.class))
        .isFalse();
    assertThat(decision.reasons()).noneMatch(reason -> reason.name().contains("EXPERT_ONLY"));
  }

  /** AI의 {@code blocked_refs} 한 건에 대응하는 근거 항목이다 — 그 원본을 신고했고 미확정 음성 발화 표시가 붙어 있다. */
  private static EvidenceCandidate blocked(long evidenceId, String messageId) {
    return new EvidenceCandidate(
        evidenceId,
        EvidenceSourceType.CHILD_ANSWER,
        "아이의 답변입니다.",
        answerRef(messageId),
        null,
        true,
        null);
  }
}
