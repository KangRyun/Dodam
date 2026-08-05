package com.ssafy.b209.report.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * 경향 해석·근거 도메인이 계약의 배타 규칙과 공개 판정을 강제하는지 검증한다 (S15P11B209-900).
 *
 * <p>DB CHECK 로는 표현할 수 없는 규칙을 여기서 막는다 — "원본 참조와 파생 목록 중 정확히 하나"는 다른 테이블의 행 존재 여부를 봐야 하므로 제약으로 쓸 수
 * 없다.
 */
class ReportPublicInterpretationTest {

  private final Report report = mock(Report.class);

  @Test
  void startsWithheldSoUnverifiedCardIsNeverVisible() {
    ReportPublicInterpretation card = card(0);

    // 기본값을 공개로 두면 두 단 검증을 건너뛴 카드가 그대로 노출된다.
    assertThat(card.getDisclosureState()).isEqualTo(ReportInterpretationDisclosureState.WITHHELD);
    assertThat(card.getDisclosureState().isGuardianVisible()).isFalse();
    assertThat(card.getWithheldReasonCode())
        .isEqualTo(ReportPublicInterpretation.PENDING_VERIFICATION);
  }

  @Test
  void publishesOnlyWhenEvidenceIsReferenced() {
    ReportPublicInterpretation card = card(0);

    assertThatThrownBy(card::publish)
        .isInstanceOf(IllegalStateException.class)
        .hasMessageContaining("without evidence");

    card.referenceEvidence(original(1));
    card.publish();

    assertThat(card.getDisclosureState().isGuardianVisible()).isTrue();
    assertThat(card.getWithheldReasonCode()).isNull();
  }

  @Test
  void keepsWithheldAndExpertOnlyAsDifferentOutcomes() {
    ReportPublicInterpretation withheld = card(0);
    withheld.withhold("INSUFFICIENT_INDEPENDENT_EVIDENCE");
    ReportPublicInterpretation restricted = card(1);
    restricted.restrictToExpert("FIXED_TRAIT_EXPRESSION");

    // 구조 게이트 실패는 제외이고 표현 필터 실패는 강등이다. 한 상태로 묶으면 검토해도 공개할 수 없는
    // 항목이 전문가 검토 대기열에 쌓인다(계약 §4-3).
    assertThat(withheld.getDisclosureState())
        .isEqualTo(ReportInterpretationDisclosureState.WITHHELD);
    assertThat(restricted.getDisclosureState())
        .isEqualTo(ReportInterpretationDisclosureState.EXPERT_ONLY);
    assertThat(withheld.getDisclosureState().isGuardianVisible()).isFalse();
    assertThat(restricted.getDisclosureState().isGuardianVisible()).isFalse();
  }

  @Test
  void rejectsDuplicatedEvidenceReferenceSoCountIsNotInflated() {
    ReportEvidenceItem answer = original(1);
    ReportPublicInterpretation card = card(0);
    card.referenceEvidence(answer);

    assertThatThrownBy(() -> card.referenceEvidence(answer))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("already referenced");
    assertThat(card.getEvidences()).hasSize(1);
  }

  @Test
  void numbersEvidenceReferencesInInsertionOrder() {
    ReportPublicInterpretation card = card(0);
    card.referenceEvidence(original(1));
    card.referenceEvidence(original(2));

    assertThat(card.getEvidences())
        .extracting(ReportInterpretationEvidence::getDisplayOrder)
        .containsExactly(0, 1);
  }

  @Test
  void rejectsBlankTitleAndTendencyText() {
    assertThatThrownBy(
            () ->
                ReportPublicInterpretation.create(
                    report, 0, ReportInterpretationCategory.EMOTION, " ", "경향", null, null))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("title");
    assertThatThrownBy(
            () ->
                ReportPublicInterpretation.create(
                    report, 0, ReportInterpretationCategory.EMOTION, "제목", " ", null, null))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("tendencyText");
  }

  @Test
  void rejectsNegativeDisplayOrderBecauseItIsReferencedByIndex() {
    assertThatThrownBy(
            () ->
                ReportPublicInterpretation.create(
                    report, -1, ReportInterpretationCategory.EMOTION, "제목", "경향", null, null))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("displayOrder");
  }

  @Test
  void requiresSourceReferenceForOriginalEvidence() {
    assertThatThrownBy(
            () ->
                ReportEvidenceItem.original(
                    report,
                    1,
                    ReportEvidenceSourceType.CHILD_ANSWER,
                    "근거",
                    ReportEvidenceSourceKind.QA_ANSWER,
                    " ",
                    false))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("sourceRefId");
  }

  @Test
  void rejectsDerivedTypeOnOriginalFactory() {
    assertThatThrownBy(
            () ->
                ReportEvidenceItem.original(
                    report,
                    1,
                    ReportEvidenceSourceType.REPEATED_SUBJECT,
                    "근거",
                    ReportEvidenceSourceKind.QA_ANSWER,
                    "202",
                    false))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("derived sourceType");
  }

  @Test
  void rejectsOriginalTypeOnDerivedFactory() {
    assertThatThrownBy(
            () ->
                ReportEvidenceItem.derived(
                    report,
                    1,
                    ReportEvidenceSourceType.CHILD_ANSWER,
                    "근거",
                    List.of(new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "202")),
                    false))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("non-derived sourceType");
  }

  @Test
  void rejectsDerivedEvidenceWithoutOrigin() {
    // 원본이 없으면 말단까지 펼쳐 세는 계수 절차가 0건이 되어 근거로 쓸 수 없다.
    assertThatThrownBy(
            () ->
                ReportEvidenceItem.derived(
                    report, 1, ReportEvidenceSourceType.LONGITUDINAL, "근거", List.of(), false))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("at least one origin");
  }

  @Test
  void exposesSourceReferenceOnlyForOriginalEvidence() {
    ReportEvidenceItem originalItem = original(1);
    ReportEvidenceItem derivedItem =
        ReportEvidenceItem.derived(
            report,
            2,
            ReportEvidenceSourceType.REPEATED_SUBJECT,
            "근거",
            List.of(new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "202")),
            false);

    assertThat(originalItem.isDerived()).isFalse();
    assertThat(originalItem.getSourceRef()).isPresent();
    assertThat(derivedItem.isDerived()).isTrue();
    assertThat(derivedItem.getSourceRef()).isEmpty();
    assertThat(derivedItem.getDerivations()).hasSize(1);
  }

  @Test
  void treatsSameReferenceValueAsOneForCounting() {
    // 독립 근거 계수가 값 동등성에 의존하므로 record 로 둔다.
    assertThat(new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "202"))
        .isEqualTo(new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "202"));
    // 말단 참조를 합집합으로 모을 때 같은 값이 1건으로 접히는지 — 계수 알고리즘이 이 성질에 기댄다.
    assertThat(
            new java.util.HashSet<>(
                List.of(
                    new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "202"),
                    new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "202"),
                    new ReportEvidenceSourceRef(ReportEvidenceSourceKind.QA_ANSWER, "203"))))
        .hasSize(2);
  }

  @Test
  void distinguishesChildExpressionSourceTypes() {
    assertThat(ReportEvidenceSourceType.CHILD_ANSWER.isChildExpression()).isTrue();
    assertThat(ReportEvidenceSourceType.SELECTED_EMOTION.isChildExpression()).isTrue();
    assertThat(ReportEvidenceSourceType.STATED_EMOTION.isChildExpression()).isTrue();
    assertThat(ReportEvidenceSourceType.VISION.isChildExpression()).isFalse();
    assertThat(ReportEvidenceSourceType.ACTIVITY_METRIC.isChildExpression()).isFalse();
  }

  @Test
  void rejectsBlankGuidance() {
    assertThatThrownBy(
            () -> ReportParentGuide.create(report, ReportParentGuideType.HOME_OBSERVATION, 0, " "))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("guidance");
  }

  private ReportPublicInterpretation card(int displayOrder) {
    return ReportPublicInterpretation.create(
        report,
        displayOrder,
        ReportInterpretationCategory.RELATIONSHIP,
        "가족과의 정서적 연결",
        "가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.",
        "이번 그림 활동에서 나타난 가능성입니다.",
        "새로운 상황에서도 보호자의 확인을 반복해서 구하는지 살펴봐 주세요.");
  }

  private ReportEvidenceItem original(int evidenceNumber) {
    return ReportEvidenceItem.original(
        report,
        evidenceNumber,
        ReportEvidenceSourceType.CHILD_ANSWER,
        "근거 문장 " + evidenceNumber,
        ReportEvidenceSourceKind.QA_ANSWER,
        "20" + evidenceNumber,
        false);
  }
}
