package com.ssafy.b209.report.safety;

import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.activityMetric;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.answerRef;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.childAnswer;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.longitudinal;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.pool;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.ref;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.repeatedSubject;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.selectedEmotion;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.statedEmotion;
import static com.ssafy.b209.report.safety.InterpretationSafetyFixtures.vision;
import static org.assertj.core.api.Assertions.assertThat;

import java.util.Arrays;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

/** 독립 근거 계수 — 원본 단위 판정, 병합 묶음, 파생 전개, 순환 방어를 고정한다. */
class IndependentEvidenceCounterTest {

  private final IndependentEvidenceCounter counter = new IndependentEvidenceCounter();

  @Test
  void countsSameSourceTypeFromDifferentOriginsAsTwo() {
    // 집에 대한 답변과 사람에 대한 답변은 둘 다 CHILD_ANSWER지만 서로 다른 메시지다.
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), childAnswer(2L, "307"));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(2);
    assertThat(expansion.childExpressionPresent()).isTrue();
    assertThat(expansion.issues()).isEmpty();
  }

  @Test
  void countsSameOriginReportedAsTwoTypesAsOne() {
    // 같은 답변 메시지를 CHILD_ANSWER와 STATED_EMOTION 두 종류로 신고해도 원본은 하나다.
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), statedEmotion(2L, "202"));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
  }

  @Test
  void countsDerivedEvidenceAndItsOriginAsOne() {
    Map<Long, EvidenceCandidate> pool =
        pool(childAnswer(1L, "202"), repeatedSubject(2L, answerRef("202")));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
    assertThat(expansion.issues()).isEmpty();

    // 대조군 — 파생이 다른 원본을 가리키면 2건이 된다. 위 1건이 "항상 1"이 아님을 못박는다.
    EvidenceExpansion twoOrigins =
        counter.expand(
            List.of(1L, 2L), pool(childAnswer(1L, "202"), repeatedSubject(2L, answerRef("307"))));
    assertThat(twoOrigins.independentEvidenceCount()).isEqualTo(2);
  }

  @Test
  void expandsDerivedEvidenceToEveryOriginItCarries() {
    // 파생 근거 하나가 서로 다른 원본 둘을 담으면 그 자체로 2건이다 — 그것이 파생의 뜻이다.
    Map<Long, EvidenceCandidate> pool =
        pool(repeatedSubject(1L, answerRef("202"), answerRef("307")));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(2);
    assertThat(expansion.childExpressionPresent()).isTrue();
    assertThat(expansion.issues()).isEmpty();
  }

  @Test
  void treatsDerivedOriginAsLeafEvenWhenNoEvidenceItemCarriesIt() {
    // derivedFrom은 원본 참조 목록이다. 그 원본이 근거 항목으로 함께 실려 있지 않아도 참조 자체가 말단이다.
    Map<Long, EvidenceCandidate> pool =
        pool(repeatedSubject(1L, answerRef("202"), answerRef("307")), childAnswer(2L, "999"));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(2);
    assertThat(expansion.issues()).isEmpty();
  }

  @Test
  void treatsDerivedEvidenceAsChildExpressionWhenLeafKindIsChildExpression() {
    // 파생 항목 자체의 sourceType은 REPEATED_SUBJECT라 아이 표현이 아니다. 말단 참조의 kind로만 충족된다.
    Map<Long, EvidenceCandidate> pool =
        pool(repeatedSubject(1L, answerRef("202"), answerRef("307")));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool);

    assertThat(expansion.childExpressionPresent()).isTrue();
  }

  @Test
  void doesNotTreatDerivedEvidenceFromVisionOriginsAsChildExpression() {
    Map<Long, EvidenceCandidate> pool =
        pool(
            longitudinal(
                1L,
                ref(EvidenceSourceKind.DETECTED_OBJECT, "d1"),
                ref(EvidenceSourceKind.VLM_OBSERVATION, "v1")));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(2);
    assertThat(expansion.childExpressionPresent()).isFalse();
  }

  @Test
  void mergesSelectedAndStatedEmotionIntoOne() {
    Map<Long, EvidenceCandidate> pool = pool(selectedEmotion(1L, "11"), statedEmotion(2L, "202"));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
    assertThat(expansion.childExpressionPresent()).isTrue();
  }

  @Test
  void mergesEmotionEvidenceRegardlessOfWhichActivityItCameFrom() {
    // 병합 묶음은 카드 전역이다. 활동을 나눠도 "같은 감정을 두 번 신고한 것"과 구분할 수 없어 합치는 쪽이 보수적이다.
    Map<Long, EvidenceCandidate> pool =
        pool(
            selectedEmotion(1L, "11"),
            selectedEmotion(2L, "48"),
            statedEmotion(3L, "202"),
            statedEmotion(4L, "911"));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L, 3L, 4L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
  }

  @Test
  void foldsMergeFamiliesBeforeTakingTheUnionOfOrigins() {
    // 접기를 합집합보다 나중에 하면 사라져야 할 감정 근거의 원본이 이미 합집합에 들어가 3건이 된다.
    Map<Long, EvidenceCandidate> pool =
        pool(selectedEmotion(1L, "11"), statedEmotion(2L, "202"), childAnswer(3L, "307"));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L, 3L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(2);
    assertThat(expansion.childExpressionPresent()).isTrue();
  }

  @Test
  void mergesAnyNumberOfActivityMetricsIntoOne() {
    Map<Long, EvidenceCandidate> pool =
        pool(activityMetric(1L, "m1"), activityMetric(2L, "m2"), activityMetric(3L, "m3"));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L, 3L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
    assertThat(expansion.childExpressionPresent()).isFalse();
  }

  @Test
  void countsVisionEvidenceFromDifferentRowsSeparately() {
    Map<Long, EvidenceCandidate> pool = pool(vision(1L, "71"), vision(2L, "72"));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L), pool);

    // VISION에는 병합 묶음이 없다 — 2건으로 세되 아이 표현 근거는 없다.
    assertThat(expansion.independentEvidenceCount()).isEqualTo(2);
    assertThat(expansion.childExpressionPresent()).isFalse();
  }

  @Test
  void distinguishesSameRowIdFromDifferentKinds() {
    Map<Long, EvidenceCandidate> pool = pool(childAnswer(1L, "202"), vision(2L, "202"));

    EvidenceExpansion expansion = counter.expand(List.of(1L, 2L), pool);

    // 서로 다른 테이블의 같은 행 번호는 같은 원본이 아니다.
    assertThat(expansion.independentEvidenceCount()).isEqualTo(2);
  }

  @Test
  void countsRepeatedOriginReferenceInsideOneDerivedEvidenceOnce() {
    Map<Long, EvidenceCandidate> pool =
        pool(repeatedSubject(1L, answerRef("202"), answerRef("202")));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool);

    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
    assertThat(expansion.issues()).isEmpty();
  }

  @Test
  @Timeout(5)
  void terminatesWhenNestedDerivationsPointAtEachOther() {
    // 중첩 파생은 배타 규칙 위반이라 카드가 직접 참조하면 걸러진다. 전개 도중 만나도 스택을 넘기지 않고 사유로 끝나야 한다.
    EvidenceCandidate nestedA = nested(1L, answerRef("202"), answerRef("307"));
    EvidenceCandidate nestedB = nested(2L, answerRef("307"), answerRef("202"));
    EvidenceCandidate entry = repeatedSubject(3L, answerRef("202"));

    EvidenceExpansion expansion = counter.expand(List.of(3L), pool(nestedA, nestedB, entry));

    assertThat(expansion.issues()).contains(InterpretationExclusionReason.EVIDENCE_CYCLE_DETECTED);
    assertThat(expansion.independentEvidenceCount()).isZero();
    assertThat(expansion.childExpressionPresent()).isFalse();
  }

  @Test
  @Timeout(5)
  void terminatesWhenNestedDerivationPointsAtItself() {
    EvidenceCandidate selfNested = nested(1L, answerRef("202"), answerRef("202"));
    EvidenceCandidate entry = repeatedSubject(2L, answerRef("202"));

    EvidenceExpansion expansion = counter.expand(List.of(2L), pool(selfNested, entry));

    assertThat(expansion.issues()).contains(InterpretationExclusionReason.EVIDENCE_CYCLE_DETECTED);
  }

  @Test
  @Timeout(5)
  void collectsOriginsReachableAroundACycle() {
    EvidenceCandidate selfNested = nested(1L, answerRef("202"), answerRef("202"));
    EvidenceCandidate entry = repeatedSubject(2L, answerRef("202"), answerRef("307"));

    EvidenceExpansion expansion = counter.expand(List.of(2L), pool(selfNested, entry));

    // 순환을 끊고도 그 경로 밖의 원본은 정상 수집한다.
    assertThat(expansion.issues()).contains(InterpretationExclusionReason.EVIDENCE_CYCLE_DETECTED);
    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
    assertThat(expansion.childExpressionPresent()).isTrue();
  }

  @Test
  void reportsMissingEvidenceRefs() {
    EvidenceExpansion nullRefs = counter.expand(null, pool(childAnswer(1L, "202")));
    EvidenceExpansion emptyRefs = counter.expand(List.of(), pool(childAnswer(1L, "202")));

    assertThat(nullRefs.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_REF_MISSING);
    assertThat(emptyRefs.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_REF_MISSING);
  }

  @Test
  void reportsUnresolvedEvidenceRef() {
    EvidenceExpansion expansion = counter.expand(List.of(1L, 99L), pool(childAnswer(1L, "202")));

    assertThat(expansion.issues()).contains(InterpretationExclusionReason.EVIDENCE_REF_UNRESOLVED);
    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
  }

  @Test
  void reportsUnresolvedRefWhenDerivedFromCarriesNull() {
    EvidenceCandidate withNullOrigin =
        EvidenceCandidate.derived(
            1L,
            EvidenceSourceType.REPEATED_SUBJECT,
            "여러 그림에서 반복되었습니다.",
            Arrays.asList(answerRef("202"), null));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool(withNullOrigin));

    assertThat(expansion.issues()).contains(InterpretationExclusionReason.EVIDENCE_REF_UNRESOLVED);
    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
  }

  @Test
  void rejectsCompositeKeyIdentifier() {
    EvidenceCandidate composite =
        EvidenceCandidate.source(
            1L,
            EvidenceSourceType.VISION,
            "그림에서 확인한 내용입니다.",
            ref(EvidenceSourceKind.DETECTED_OBJECT, "884:HOUSE:3"));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool(composite));

    assertThat(expansion.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_SOURCE_REF_UNRESOLVABLE);
    assertThat(expansion.independentEvidenceCount()).isZero();
  }

  @Test
  void rejectsCompositeKeyIdentifierReachedThroughDerivedEvidence() {
    Map<Long, EvidenceCandidate> pool =
        pool(
            repeatedSubject(
                1L, answerRef("202"), ref(EvidenceSourceKind.DETECTED_OBJECT, "884|HOUSE")));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool);

    // 파생으로 감싸면 형태 검증을 우회하는 경로가 없어야 한다.
    assertThat(expansion.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_SOURCE_REF_UNRESOLVABLE);
    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
  }

  @Test
  void acceptsNonNumericServerIssuedIdentifiers() {
    // 저장 컬럼이 VARCHAR(64) 문자열이고 활동 지표·탐지 객체 식별자가 숫자가 아닐 수 있다.
    assertThat(unresolvableFor("m1")).isFalse();
    assertThat(unresolvableFor("d1")).isFalse();
    assertThat(unresolvableFor("0")).isFalse();
    assertThat(unresolvableFor("007")).isFalse();
    assertThat(unresolvableFor("A-102")).isFalse();
    assertThat(unresolvableFor("102")).isFalse();
  }

  @Test
  void rejectsIdentifiersThatLookLikeCompositeKeys() {
    assertThat(unresolvableFor("")).isTrue();
    assertThat(unresolvableFor("102 ")).isTrue();
    assertThat(unresolvableFor("884:HOUSE:3")).isTrue();
    assertThat(unresolvableFor("884|3")).isTrue();
    assertThat(unresolvableFor("884/3")).isTrue();
    assertThat(unresolvableFor("884+HOUSE")).isTrue();
    assertThat(unresolvableFor("884,3")).isTrue();
    assertThat(unresolvableFor("884;3")).isTrue();
    assertThat(unresolvableFor("884#3")).isTrue();
    assertThat(unresolvableFor("analysisId=884")).isTrue();
    assertThat(unresolvableFor("884@HOUSE")).isTrue();
    assertThat(unresolvableFor("1".repeat(65))).isTrue();
    assertThat(unresolvableFor("1".repeat(64))).isFalse();
  }

  @Test
  void rejectsSourceRefWithoutKind() {
    EvidenceCandidate noKind =
        EvidenceCandidate.source(
            1L, EvidenceSourceType.CHILD_ANSWER, "아이의 답변입니다.", new EvidenceSourceRef(null, "202"));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool(noKind));

    assertThat(expansion.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_SOURCE_REF_UNRESOLVABLE);
  }

  @Test
  void rejectsEvidenceWithUnknownSourceType() {
    EvidenceCandidate unknownType =
        EvidenceCandidate.source(
            1L, EvidenceSourceType.fromCode("PARENT_REPORT"), "보호자가 전한 내용입니다.", answerRef("202"));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool(unknownType));

    assertThat(expansion.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_SOURCE_TYPE_UNKNOWN);
    // 종류를 몰라도 원본 참조는 유효하므로 계수에서는 살아 있다 — 카드는 사유 때문에 제외된다.
    assertThat(expansion.independentEvidenceCount()).isEqualTo(1);
  }

  @Test
  void rejectsEvidenceHavingBothSourceRefAndDerivedFrom() {
    EvidenceCandidate both = nested(1L, answerRef("202"), answerRef("307"));

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool(both));

    assertThat(expansion.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_SOURCE_EXCLUSIVITY_VIOLATED);
    assertThat(expansion.independentEvidenceCount()).isZero();
  }

  @Test
  void rejectsEvidenceHavingNeitherSourceRefNorDerivedFrom() {
    EvidenceCandidate neither =
        new EvidenceCandidate(
            1L, EvidenceSourceType.CHILD_ANSWER, "아이의 답변입니다.", null, List.of(), false, null);

    EvidenceExpansion expansion = counter.expand(List.of(1L), pool(neither));

    assertThat(expansion.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_SOURCE_EXCLUSIVITY_VIOLATED);
  }

  @Test
  void reportsUnconfirmedSttEvidence() {
    EvidenceCandidate unconfirmed =
        new EvidenceCandidate(
            1L, EvidenceSourceType.CHILD_ANSWER, "아이의 답변입니다.", answerRef("202"), null, true, null);

    EvidenceExpansion expansion =
        counter.expand(List.of(1L, 2L), pool(unconfirmed, childAnswer(2L, "307")));

    assertThat(expansion.issues())
        .containsExactly(InterpretationExclusionReason.EVIDENCE_STT_UNCONFIRMED);
  }

  @Test
  void reportsCrisisEvidenceEvenWhenReachedThroughDerivedEvidence() {
    EvidenceCandidate crisis =
        new EvidenceCandidate(
            1L,
            EvidenceSourceType.CHILD_ANSWER,
            "아이의 답변입니다.",
            answerRef("202"),
            null,
            false,
            EvidenceCrisisReason.ABUSE_DISCLOSURE);

    EvidenceExpansion expansion =
        counter.expand(List.of(2L), pool(crisis, repeatedSubject(2L, answerRef("202"))));

    // 파생 근거를 거쳐 도달한 위기 메시지도 잡아야 한다 — 파생으로 감싸면 통과하는 우회를 막는다.
    assertThat(expansion.issues()).contains(InterpretationExclusionReason.EVIDENCE_CRISIS_MESSAGE);
  }

  /** 원본 참조와 파생을 함께 가진 배타 규칙 위반 항목이다. 전개 도중 만났을 때의 종료를 확인하는 데 쓴다. */
  private static EvidenceCandidate nested(
      long evidenceId, EvidenceSourceRef sourceRef, EvidenceSourceRef derivedFrom) {
    return new EvidenceCandidate(
        evidenceId,
        EvidenceSourceType.REPEATED_SUBJECT,
        "여러 그림에서 반복되었습니다.",
        sourceRef,
        List.of(derivedFrom),
        false,
        null);
  }

  private boolean unresolvableFor(String sourceId) {
    EvidenceCandidate candidate =
        EvidenceCandidate.source(
            1L, EvidenceSourceType.CHILD_ANSWER, "아이의 답변입니다.", answerRef(sourceId));
    return counter
        .expand(List.of(1L), pool(candidate))
        .issues()
        .contains(InterpretationExclusionReason.EVIDENCE_SOURCE_REF_UNRESOLVABLE);
  }
}
