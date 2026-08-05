package com.ssafy.b209.report.safety;

import java.util.Collections;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 안전 검증 <strong>1단 — 구조적 공개 게이트</strong>다(보호자 계약 §4-3, 875 계약 §4-1·§4-2).
 *
 * <p>실패하면 <strong>해당 카드만 미공개(제외)</strong>하고 사유 코드를 남긴다. <strong>EXPERT_ONLY 강등이 아니다</strong> — 근거
 * 자체가 없으므로 표현을 다듬어도 공개 대상이 아니다. 강등은 2단({@link InterpretationExpressionFilter})만 만든다. 리포트 전체를 실패시키지
 * 않고 문제 항목만 제외한다.
 *
 * <p>공개 조건(모두 충족):
 *
 * <ul>
 *   <li>독립 근거 2건 이상 — {@link IndependentEvidenceCounter}가 병합 묶음을 접은 뒤 말단 합집합으로 센다
 *   <li>아이 표현 근거 1건 이상 — 말단 참조의 {@link EvidenceSourceKind#isChildExpression() kind}로 판정하므로 파생 근거도
 *       말단이 아이 표현이면 충족
 *   <li>참조 정합 — 실존 {@code evidenceId}, {@code sourceRef} XOR {@code derivedFrom}, 조합키가 아닌 단일 식별자
 *   <li>{@code category}가 허용된 관찰 관점 라벨이고 {@code scopeText}·{@code homeObservationGuide}가 비어 있지 않음
 *   <li>{@code tendencyText}가 가능성 어조
 *   <li>근거로 쓸 수 없는 항목(미확정 음성 발화·위기 사유 메시지)이 섞이지 않음
 * </ul>
 *
 * <p>이 게이트는 값싼 결정적 검사만 하므로 표현 안전 필터보다 먼저 돌린다.
 */
public final class InterpretationPublicationGate {

  /**
   * 가능성 어조로 인정하는 표지다.
   *
   * <p>계약이 "{@code tendencyText}는 반드시 가능성 어조"라고 <em>요구</em>하므로, 금지 표현을 찾는 2단과 달리 여기서는 표지를 하나도 찾지
   * 못하면 실패로 본다(fail-closed). 근거가 아니라 어조만 보는 검사이므로 허용 목록이 좁아도 결과는 "그 카드만 미공개"에 그친다.
   *
   * <p><strong>AI {@code ai/report_client.py}의 {@code _TENTATIVE_MARKERS}와 문자 단위로 같은 6종이다.</strong>
   * 같은 어조 규칙을 두 곳에서 집행하는데 BE가 더 관대하면 AI가 버린 문장을 BE가 통과시켜 "AI 경로에서는 안 나오는데 다른 경로에서는 나오는" 카드가 생긴다.
   * 그래서 넓히지 않고 맞춘다.
   *
   * <p>AI가 부분 문자열 포함({@code marker in tendency})으로 검사하므로 정규식이 아니라 {@link
   * String#contains(CharSequence)}를 쓴다. 정규식으로 옮기면 공백 허용({@code 수\s*있}) 같은 완화가 조용히 끼어들어 판정이 갈린다.
   */
  private static final List<String> POSSIBILITY_TONE_MARKERS =
      List.of("수 있", "보입니다", "보여요", "경향", "듯", "가능성");

  private final IndependentEvidenceCounter counter;

  /** 기본 계산기를 쓰는 게이트를 만든다. */
  public InterpretationPublicationGate() {
    this(new IndependentEvidenceCounter());
  }

  /**
   * 계산기를 주입해 게이트를 만든다.
   *
   * @param counter 독립 근거 계산기
   */
  public InterpretationPublicationGate(IndependentEvidenceCounter counter) {
    this.counter = counter;
  }

  /**
   * 카드 한 건이 구조적 공개 조건을 충족하는지 검사한다.
   *
   * @param candidate 검사할 경향 해석 카드
   * @param evidencePool {@code evidenceId}로 찾을 수 있는 근거 풀
   * @return 검사 결과이며 사유가 비어 있으면 통과
   */
  public Decision inspect(
      InterpretationCandidate candidate, Map<Long, EvidenceCandidate> evidencePool) {
    Set<InterpretationExclusionReason> reasons =
        EnumSet.noneOf(InterpretationExclusionReason.class);

    if (candidate.category() == null) {
      reasons.add(InterpretationExclusionReason.CATEGORY_NOT_ALLOWED);
    }
    if (isBlank(candidate.scopeText())) {
      reasons.add(InterpretationExclusionReason.SCOPE_TEXT_MISSING);
    }
    if (isBlank(candidate.homeObservationGuide())) {
      reasons.add(InterpretationExclusionReason.HOME_OBSERVATION_GUIDE_MISSING);
    }
    if (isBlank(candidate.tendencyText())) {
      reasons.add(InterpretationExclusionReason.TENDENCY_TEXT_MISSING);
    } else if (!hasPossibilityTone(candidate.tendencyText())) {
      reasons.add(InterpretationExclusionReason.TENDENCY_TEXT_NOT_POSSIBILITY_TONE);
    }

    EvidenceExpansion expansion = counter.expand(candidate.evidenceRefs(), evidencePool);
    reasons.addAll(expansion.issues());
    if (expansion.independentEvidenceCount()
        < IndependentEvidenceCounter.MINIMUM_INDEPENDENT_EVIDENCE) {
      reasons.add(InterpretationExclusionReason.INDEPENDENT_EVIDENCE_INSUFFICIENT);
    }
    if (!expansion.childExpressionPresent()) {
      reasons.add(InterpretationExclusionReason.CHILD_EXPRESSION_EVIDENCE_MISSING);
    }
    return new Decision(Collections.unmodifiableSet(reasons), expansion.independentEvidenceCount());
  }

  /**
   * 카드 한 건에 대한 1단 판정이다.
   *
   * @param reasons 제외 사유 집합이며 비어 있으면 통과
   * @param independentEvidenceCount 병합 상한을 적용한 뒤 센 독립 근거 수
   */
  public record Decision(Set<InterpretationExclusionReason> reasons, int independentEvidenceCount) {

    /**
     * 1단을 통과했는지 판단한다.
     *
     * @return 제외 사유가 하나도 없으면 {@code true}
     */
    public boolean passed() {
      return reasons.isEmpty();
    }
  }

  /**
   * 문장이 가능성 어조 표지를 담고 있는지 판정한다.
   *
   * @param text 검사할 문장
   * @return 표지를 하나 이상 담고 있으면 {@code true}
   */
  static boolean hasPossibilityTone(String text) {
    return POSSIBILITY_TONE_MARKERS.stream().anyMatch(text::contains);
  }

  /**
   * 가능성 어조 표지 목록을 돌려준다.
   *
   * <p>AI 목록과 문자 단위로 대조하는 테스트가 쓴다.
   *
   * @return 표지 목록
   */
  static List<String> possibilityToneMarkers() {
    return POSSIBILITY_TONE_MARKERS;
  }

  private static boolean isBlank(String value) {
    return value == null || value.isBlank();
  }
}
