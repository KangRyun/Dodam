package com.ssafy.b209.report.safety;

import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.HOME_GUIDE;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.SCOPE_TEXT;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.TENDENCY_TEXT;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.activityMetric;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.answerRef;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.card;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.cardWithTendency;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.childAnswer;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.pool;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.ref;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.repeatedSubject;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.selectedEmotion;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.statedEmotion;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.vision;
import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** 1단 구조적 공개 게이트 — 공개 조건과 제외 사유를 고정한다. */
class InterpretationPublicationGateTest {

  private final InterpretationPublicationGate gate = new InterpretationPublicationGate();

  @Test
  void passesCardWithTwoIndependentOriginsIncludingChildExpression() {
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), vision(2L, "71"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.passed()).isTrue();
    assertThat(decision.reasons()).isEmpty();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
  }

  @Test
  void rejectsCardBackedOnlyByTwoEmotionEvidences() {
    Map<Long, EvidenceCandidate> pool = pool(selectedEmotion(1L, "11"), statedEmotion(2L, "202"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    // 병합 묶음 때문에 감정 근거 2건은 독립 1건이다 — 아이 표현 요건은 충족하지만 계수가 미달이다.
    assertThat(decision.independentEvidenceCount()).isEqualTo(1);
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void rejectsCardWithoutChildExpressionEvidence() {
    Map<Long, EvidenceCandidate> pool = pool(vision(1L, "71"), activityMetric(2L, "m1"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    // 독립 근거 수는 2건이라 계수 요건만으로는 걸리지 않는다 — 아이 표현 요건이 단독으로 막는다.
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.CHILD_EXPRESSION_EVIDENCE_MISSING);
  }

  @Test
  void rejectsCardWhoseEvidenceRefDoesNotResolve() {
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 99L), pool);

    assertThat(decision.reasons())
        .contains(
            InterpretationExclusionReason.EVIDENCE_REF_UNRESOLVED,
            InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void rejectsCardWithoutEvidenceRefs() {
    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(), pool(childAnswer(1L, "202")));

    assertThat(decision.reasons()).contains(InterpretationExclusionReason.EVIDENCE_REF_MISSING);
  }

  @Test
  void rejectsCardWithCompositeKeySourceIdentifier() {
    EvidenceCandidate composite =
        EvidenceCandidate.source(
            2L,
            EvidenceSourceType.VISION,
            "그림에서 확인한 내용입니다.",
            ref(EvidenceSourceKind.DETECTED_OBJECT, "884:HOUSE:3"));
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), composite);

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.reasons())
        .contains(
            InterpretationExclusionReason.EVIDENCE_SOURCE_REF_UNRESOLVABLE,
            InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void rejectsCardWithoutScopeText() {
    InterpretationCandidate noScope =
        new InterpretationCandidate(
            InterpretationCategory.EMOTION,
            "감정 표현",
            TENDENCY_TEXT,
            "   ",
            HOME_GUIDE,
            List.of(1L, 2L),
            null);

    InterpretationPublicationGate.Decision decision =
        gate.inspect(noScope, pool(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.SCOPE_TEXT_MISSING);
  }

  @Test
  void rejectsCardWithoutHomeObservationGuide() {
    InterpretationCandidate noGuide =
        new InterpretationCandidate(
            InterpretationCategory.EMOTION,
            "감정 표현",
            TENDENCY_TEXT,
            SCOPE_TEXT,
            null,
            List.of(1L, 2L),
            null);

    InterpretationPublicationGate.Decision decision =
        gate.inspect(noGuide, pool(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.HOME_OBSERVATION_GUIDE_MISSING);
  }

  @Test
  void rejectsCardWithUnknownCategory() {
    InterpretationCandidate unknownCategory =
        new InterpretationCandidate(
            InterpretationCategory.fromCode("PERSONALITY_TYPE"),
            "성격 유형",
            TENDENCY_TEXT,
            SCOPE_TEXT,
            HOME_GUIDE,
            List.of(1L, 2L),
            null);

    InterpretationPublicationGate.Decision decision =
        gate.inspect(unknownCategory, pool(childAnswer(1L, "202"), vision(2L, "71")));

    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.CATEGORY_NOT_ALLOWED);
  }

  @Test
  void rejectsAssertiveTendencyText() {
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), vision(2L, "71"));

    InterpretationPublicationGate.Decision decision =
        gate.inspect(cardWithTendency("가족에게 정서적으로 의지합니다.", 1L, 2L), pool);

    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.TENDENCY_TEXT_NOT_POSSIBILITY_TONE);
  }

  @Test
  void rejectsBlankTendencyText() {
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), vision(2L, "71"));

    InterpretationPublicationGate.Decision decision =
        gate.inspect(cardWithTendency("", 1L, 2L), pool);

    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.TENDENCY_TEXT_MISSING);
  }

  @Test
  void acceptsPossibilityToneMarkedSentences() {
    List<String> hedged =
        List.of(
            "가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.",
            "혼자 있는 시간을 편하게 느끼는 경향이 있습니다.",
            "새로운 상황을 조심스럽게 살피는 듯합니다.",
            "이야기를 나눌 때 보호자를 자주 확인하는 모습으로 보입니다.",
            "친구와 함께 있는 상황을 즐거워해 보여요.",
            "관심을 표현하려는 가능성이 있습니다.");

    for (String text : hedged) {
      assertThat(InterpretationPublicationGate.hasPossibilityTone(text))
          .withFailMessage("가능성 어조를 과잉 차단했습니다: %s", text)
          .isTrue();
    }
  }

  @Test
  void rejectsAssertiveToneVariants() {
    List<String> assertive =
        List.of("가족에게 정서적으로 의지합니다.", "혼자 있는 시간을 좋아합니다.", "새로운 상황을 두려워한다.", "친구와 잘 어울린다.");

    for (String text : assertive) {
      assertThat(InterpretationPublicationGate.hasPossibilityTone(text))
          .withFailMessage("단정 어조를 통과시켰습니다: %s", text)
          .isFalse();
    }
  }

  @Test
  void rejectsHedgedSentencesThatAiAlsoRejects() {
    // 표지를 AI 6종으로 줄인 결과 이제 탈락하는 문장들이다. BE가 AI보다 관대하지 않다는 것을 못 박는다.
    List<String> noLongerAccepted =
        List.of(
            "이야기를 나눌 때 보호자를 자주 확인하는 모습을 보였어요.", // 모습 · 보였어요 — 둘 다 AI 표지가 아니다
            "친구와 함께 있는 상황을 즐거워하는 것 같아요.", // 것 같 — AI 표지가 아니다
            "혼자 있는 시간을 편하게 느낄지도 모릅니다.", // 일지도 — AI 표지가 아니다
            "보호자를 자주 확인하는 모습이 보이는 활동이었어요.", // 보이는 — AI는 보여요·보입니다만 본다
            "가족에게 의지하려는 경우가 있을수있습니다."); // 공백 없는 "수있" — AI는 "수 있"만 본다

    for (String text : noLongerAccepted) {
      assertThat(InterpretationPublicationGate.hasPossibilityTone(text))
          .withFailMessage("AI가 버리는 문장을 BE가 통과시켰습니다: %s", text)
          .isFalse();
    }
  }

  @Test
  void rejectsCardBuiltOnUnconfirmedSttEvidence() {
    EvidenceCandidate unconfirmed =
        new EvidenceCandidate(
            2L, EvidenceSourceType.CHILD_ANSWER, "아이의 답변입니다.", answerRef("307"), null, true, null);
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), unconfirmed);

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    // 계수·아이 표현 요건은 충족하지만 근거로 쓸 수 없는 항목이 섞였다.
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_STT_UNCONFIRMED);
  }

  @Test
  void rejectsCardBuiltOnCrisisEvidence() {
    EvidenceCandidate crisis =
        new EvidenceCandidate(
            2L,
            EvidenceSourceType.CHILD_ANSWER,
            "아이의 답변입니다.",
            answerRef("307"),
            null,
            false,
            EvidenceCrisisReason.SELF_HARM_RISK);
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), crisis);

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_CRISIS_MESSAGE);
  }

  @Test
  void passesCardWhoseTwoAnswersShareSourceTypeButNotOrigin() {
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), childAnswer(2L, "307"));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.passed()).isTrue();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
  }

  @Test
  void rejectsCardWhoseDerivedEvidenceCollapsesOntoItsOwnOrigin() {
    Map<Long, EvidenceCandidate> pool =
        pool(childAnswer(1L, "202"), repeatedSubject(2L, answerRef("202")));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L, 2L), pool);

    assertThat(decision.independentEvidenceCount()).isEqualTo(1);
    assertThat(decision.reasons())
        .containsExactly(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
  }

  @Test
  void passesCardBackedByOneDerivedEvidenceCarryingTwoChildOrigins() {
    Map<Long, EvidenceCandidate> pool =
        pool(repeatedSubject(1L, answerRef("202"), answerRef("307")));

    InterpretationPublicationGate.Decision decision = gate.inspect(card(1L), pool);

    // 파생 근거 하나가 서로 다른 아이 답변 둘을 담으면 그것으로 공개 조건을 채운다.
    assertThat(decision.passed()).isTrue();
    assertThat(decision.independentEvidenceCount()).isEqualTo(2);
  }

  @Test
  void everyReasonCodeFitsTheStorageColumn() {
    // report_public_interpretations.withheld_reason_code 는 VARCHAR(40)이다(V37).
    // 제외 사유와 강등 사유가 같은 컬럼을 쓰므로 두 enum 모두 상한을 지켜야 한다.
    List<String> codes = new ArrayList<>();
    for (InterpretationExclusionReason reason : InterpretationExclusionReason.values()) {
      codes.add(reason.name());
    }
    for (InterpretationDemotionReason reason : InterpretationDemotionReason.values()) {
      codes.add(reason.name());
    }

    assertThat(codes).hasSize(16);
    for (String code : codes) {
      assertThat(code.length())
          .withFailMessage("사유 코드가 저장 컬럼(40자)을 넘습니다: %s(%d자)", code, code.length())
          .isLessThanOrEqualTo(40);
    }
  }

  @Test
  void exclusionReasonsIterateInDeclarationOrderSoOneCanBeStored() {
    // 사유가 여러 건 겹칠 때도 저장 컬럼 한 칸에 넣을 첫 코드가 결정적이어야 한다.
    EvidenceCandidate composite =
        EvidenceCandidate.source(
            2L,
            EvidenceSourceType.VISION,
            "그림에서 확인한 내용입니다.",
            ref(EvidenceSourceKind.DETECTED_OBJECT, "884:HOUSE:3"));

    InterpretationPublicationGate.Decision decision =
        gate.inspect(card(1L, 2L), pool(childAnswer(1L, "202"), composite));

    assertThat(decision.reasons()).hasSizeGreaterThan(1);
    // 선언 순서상 EVIDENCE_SOURCE_REF_UNRESOLVABLE 가 INDEPENDENT_EVIDENCE_INSUFFICIENT 보다 앞이다.
    assertThat(decision.reasons().iterator().next())
        .isEqualTo(InterpretationExclusionReason.EVIDENCE_SOURCE_REF_UNRESOLVABLE);
  }
}
