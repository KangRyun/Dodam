package com.ssafy.b209.report.safety;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 카드가 가리키는 근거를 말단까지 펼쳐 <strong>독립 근거 수</strong>를 센다(보호자 계약 §4-3, 875 계약 §4-1).
 *
 * <p>절차는 계약이 정한 그대로이며 {@code ai/interpretation_gate.py}의 {@code evaluate}와 같은 순서다.
 *
 * <ol>
 *   <li>{@code evidenceRefs}가 가리키는 근거 항목을 카드에 실린 순서대로 모은다.
 *   <li>각 항목을 말단 원본 참조({@link EvidenceSourceRef})로 펼친다.
 *   <li><strong>병합 묶음을 먼저 접는다</strong> — 같은 {@link EvidenceMergeFamily}의 항목은 첫 건만 남긴다.
 *   <li>남은 항목의 말단 참조 합집합을 만든다. 그 크기가 독립 근거 수다.
 * </ol>
 *
 * <p>병합을 합집합보다 <strong>먼저</strong> 적용하는 순서가 결과를 바꾼다. 나중에 적용하면 접혀 사라져야 할 항목의 말단이 이미 합집합에 들어가 계수를
 * 부풀린다.
 *
 * <p><strong>독립성은 근거 종류가 아니라 원본 단위로 판정한다.</strong> 종류로 세면 같은 답변 하나를 두 종류로 신고해 2건을 만들 수 있고, 반대로 집에
 * 대한 답변과 사람에 대한 답변이 1건으로 깎인다.
 *
 * <p><strong>{@code derivedFrom}은 원본 참조 목록이다.</strong> {@code evidenceId} 참조가 아니다 — AI({@code
 * internal_contracts.ReportEvidenceItem.derived_from})와 저장 모델({@code report_evidence_derivations}의
 * {@code (source_ref_kind, source_ref_id)} 행)이 모두 이 형태다. 그래서 파생 근거를 펼친 말단은 <strong>그 참조
 * 자체</strong>이며, 참조가 가리키는 행이 근거 풀에 항목으로 실려 있지 않아도 유효한 말단이다.
 *
 * <p><strong>재귀와 순환 방어는 방어 로직이다.</strong> 현재 AI 응답 형태와 저장 구조에서는 파생 항목이 다른 파생 항목을 가리킬 수 없어(파생 행은 원본
 * 참조만 담는다) 전개 깊이가 항상 1이고 순환이 생기지 않는다. 그럼에도 두는 이유는 장차 중첩 파생이 허용될 때 이 계수가 조용히 틀리지 않게 하려는 것이다. 전개에 쓰는
 * 두 자료구조는 <strong>보장하는 것이 서로 다르다</strong>({@code walk} 참고).
 *
 * <ul>
 *   <li>{@code visited} — <strong>종료를 보장한다.</strong> 이미 전개한 원본 참조는 두 번 전개하지 않으므로 재귀 깊이가 서로 다른 참조 수로
 *       묶인다. 순환이 있어도 스택을 넘기지 않는 것은 이 집합 때문이다.
 *   <li>{@code activePath} — <strong>순환을 사유 코드로 보고한다.</strong> 지금 내려온 경로에 이미 있는 참조를 다시 만난 경우에만
 *       {@link InterpretationExclusionReason#EVIDENCE_CYCLE_DETECTED}를 남긴다. {@code visited}보다 먼저
 *       검사하기 때문에 자기 자신으로 돌아오는 순환과 같은 원본을 다른 가지에서 또 가리킨 무해한 중복이 갈린다. 이 검사가 없으면 순환은 {@code visited}에
 *       흡수되어 사유 없이 조용히 끝난다 — 종료는 되지만 계수가 틀린 것을 알 수 없다.
 * </ul>
 *
 * <p>그래서 순환 입력의 처리 결과를 타임아웃이 아니라 사유 코드로 단언할 수 있다.
 *
 * <p><strong>enum 두 벌에 대한 메모:</strong> 저장 계층(S15P11B209-900)에 {@code
 * ReportEvidenceSourceType}·{@code ReportEvidenceSourceKind}가 같은 값 집합으로 존재한다. 이 패키지가 자기 enum을 쓰는 것은
 * 이 브랜치의 기준 커밋에 900 산출물이 아직 없어 참조하면 컴파일되지 않기 때문이며(rebase는 하지 않는다), 값이 갈리지 않도록 어댑터 이슈에서 저장 계층 타입으로
 * 합치는 것이 목표다.
 */
public final class IndependentEvidenceCounter {

  /** 병합 묶음을 접은 뒤 카드가 공개되기 위해 필요한 최소 독립 근거 수다. */
  public static final int MINIMUM_INDEPENDENT_EVIDENCE = 2;

  /** 상태 없는 계산기다. */
  public IndependentEvidenceCounter() {}

  /**
   * 카드의 근거 참조를 말단까지 펼쳐 독립 근거 수를 센다.
   *
   * @param evidenceRefs 카드가 가리키는 {@code evidenceId} 목록이며 없으면 {@code null}
   * @param evidencePool {@code evidenceId}로 찾을 수 있는 근거 풀
   * @return 전개 결과
   */
  public EvidenceExpansion expand(
      List<Long> evidenceRefs, Map<Long, EvidenceCandidate> evidencePool) {
    Set<InterpretationExclusionReason> issues = EnumSet.noneOf(InterpretationExclusionReason.class);
    if (evidenceRefs == null || evidenceRefs.isEmpty()) {
      issues.add(InterpretationExclusionReason.EVIDENCE_REF_MISSING);
      return new EvidenceExpansion(0, false, Collections.unmodifiableSet(issues));
    }

    Map<Long, EvidenceCandidate> pool = evidencePool == null ? Map.of() : evidencePool;
    Map<EvidenceSourceRef, List<EvidenceCandidate>> originIndex = indexByOrigin(pool);

    List<ExpandedEvidence> expanded = new ArrayList<>();
    for (Long ref : evidenceRefs) {
      EvidenceCandidate item = ref == null ? null : pool.get(ref);
      if (item == null) {
        issues.add(InterpretationExclusionReason.EVIDENCE_REF_UNRESOLVED);
        continue;
      }
      if (item.sourceType() == null) {
        issues.add(InterpretationExclusionReason.EVIDENCE_SOURCE_TYPE_UNKNOWN);
      }
      boolean hasSourceRef = item.sourceRef() != null;
      if (hasSourceRef == item.isDerived()) {
        // 배타 규칙 위반이다. 이 항목이 무엇을 근거로 하는지 확정할 수 없으므로 계수에서 뺀다.
        issues.add(InterpretationExclusionReason.EVIDENCE_SOURCE_EXCLUSIVITY_VIOLATED);
        continue;
      }
      expanded.add(new ExpandedEvidence(item, leavesOf(item, originIndex, issues)));
    }

    List<ExpandedEvidence> counted = foldMergeFamilies(expanded);
    Set<EvidenceSourceRef> leaves = new LinkedHashSet<>();
    boolean childExpressionPresent = false;
    for (ExpandedEvidence entry : counted) {
      leaves.addAll(entry.leaves());
      childExpressionPresent |= entry.hasChildExpression();
    }
    return new EvidenceExpansion(
        leaves.size(), childExpressionPresent, Collections.unmodifiableSet(issues));
  }

  /**
   * 원본 참조로 근거 항목을 되찾을 수 있게 색인한다.
   *
   * <p>파생 근거를 펼칠 때 참조가 가리키는 항목의 배제 여부(미확정 음성 발화·위기 사유)를 확인하는 데 쓴다. 같은 원본을 여러 항목이 신고할 수 있으므로 값이
   * 목록이다.
   */
  private static Map<EvidenceSourceRef, List<EvidenceCandidate>> indexByOrigin(
      Map<Long, EvidenceCandidate> pool) {
    Map<EvidenceSourceRef, List<EvidenceCandidate>> index = new LinkedHashMap<>();
    for (EvidenceCandidate item : pool.values()) {
      if (item == null || item.sourceRef() == null) {
        continue;
      }
      index.computeIfAbsent(item.sourceRef(), key -> new ArrayList<>()).add(item);
    }
    return index;
  }

  /** 근거 항목 하나의 말단 원본 참조 집합을 구한다. */
  private Set<EvidenceSourceRef> leavesOf(
      EvidenceCandidate item,
      Map<EvidenceSourceRef, List<EvidenceCandidate>> originIndex,
      Set<InterpretationExclusionReason> issues) {
    Set<EvidenceSourceRef> leaves = new LinkedHashSet<>();
    recordUnusable(item, issues);
    if (item.sourceRef() != null) {
      collectLeaf(item.sourceRef(), leaves, issues);
      return leaves;
    }
    Deque<EvidenceSourceRef> activePath = new ArrayDeque<>();
    Set<EvidenceSourceRef> visited = new HashSet<>();
    for (EvidenceSourceRef parent : item.derivedFrom()) {
      walk(parent, originIndex, activePath, visited, leaves, issues);
    }
    return leaves;
  }

  /**
   * 파생 근거가 가리킨 원본 참조 하나를 전개한다.
   *
   * <p>참조가 가리키는 항목이 그 자체로 또 파생이면 한 단 더 내려간다. 현재 계약·저장 형태에서 그런 항목은 배타 규칙 위반이라 카드가 직접 참조했다면 위에서 걸러진다.
   * 그래도 전개를 형태에 무관하게 써 두는 이유는 <strong>종료 보장이 검증 순서에 의존하지 않게</strong> 하려는 것이다 — 배타 규칙 검사가 나중에 완화되거나
   * 중첩 파생이 허용되어도 이 전개는 스택을 넘기지 않고 사유 코드로 끝난다.
   */
  private void walk(
      EvidenceSourceRef ref,
      Map<EvidenceSourceRef, List<EvidenceCandidate>> originIndex,
      Deque<EvidenceSourceRef> activePath,
      Set<EvidenceSourceRef> visited,
      Set<EvidenceSourceRef> leaves,
      Set<InterpretationExclusionReason> issues) {
    if (ref == null) {
      issues.add(InterpretationExclusionReason.EVIDENCE_REF_UNRESOLVED);
      return;
    }
    if (activePath.contains(ref)) {
      issues.add(InterpretationExclusionReason.EVIDENCE_CYCLE_DETECTED);
      return;
    }
    if (!visited.add(ref)) {
      // 같은 원본을 두 경로에서 가리킨 중복 참조다. 말단은 이미 모았으므로 다시 펼치지 않는다.
      return;
    }

    boolean nested = false;
    activePath.addLast(ref);
    for (EvidenceCandidate origin : originIndex.getOrDefault(ref, List.of())) {
      recordUnusable(origin, issues);
      if (origin.isDerived()) {
        nested = true;
        for (EvidenceSourceRef parent : origin.derivedFrom()) {
          walk(parent, originIndex, activePath, visited, leaves, issues);
        }
      }
    }
    activePath.removeLast();

    if (!nested) {
      collectLeaf(ref, leaves, issues);
    }
  }

  private static void collectLeaf(
      EvidenceSourceRef ref,
      Set<EvidenceSourceRef> leaves,
      Set<InterpretationExclusionReason> issues) {
    if (ref.kind() == null || !EvidenceSourceIdentifiers.isSingleIdentifier(ref.id())) {
      issues.add(InterpretationExclusionReason.EVIDENCE_SOURCE_REF_UNRESOLVABLE);
      return;
    }
    leaves.add(ref);
  }

  /**
   * 근거로 쓸 수 없는 항목을 사유로 남긴다.
   *
   * <p>전개 경로에서 만난 모든 항목에 적용한다 — 파생 근거로 감싸서 미확정 음성 발화나 위기 발화를 우회하지 못하게 한다.
   */
  private static void recordUnusable(
      EvidenceCandidate item, Set<InterpretationExclusionReason> issues) {
    if (item.sttNeedsConfirmation()) {
      issues.add(InterpretationExclusionReason.EVIDENCE_STT_UNCONFIRMED);
    }
    if (item.crisisReason() != null) {
      issues.add(InterpretationExclusionReason.EVIDENCE_CRISIS_MESSAGE);
    }
  }

  /**
   * 병합 묶음마다 첫 항목만 남긴다.
   *
   * <p>첫 건 기준은 카드에 실린 순서다. 값 비교로는 같은 감정인지 알 수 없으니 순서라도 결정적이어야 한다.
   */
  private static List<ExpandedEvidence> foldMergeFamilies(List<ExpandedEvidence> items) {
    List<ExpandedEvidence> kept = new ArrayList<>();
    Set<EvidenceMergeFamily> seen = EnumSet.noneOf(EvidenceMergeFamily.class);
    for (ExpandedEvidence entry : items) {
      EvidenceSourceType sourceType = entry.item().sourceType();
      EvidenceMergeFamily family = sourceType == null ? null : sourceType.mergeFamily();
      if (family != null && !seen.add(family)) {
        continue;
      }
      kept.add(entry);
    }
    return kept;
  }

  /** 근거 항목 하나와 그것을 펼친 말단 원본 참조들이다. */
  private record ExpandedEvidence(EvidenceCandidate item, Set<EvidenceSourceRef> leaves) {

    /**
     * 이 근거가 아이 자신의 표현에서 왔는지 판단한다.
     *
     * <p>말단 참조의 {@code kind}가 주 판정 축이고, 항목 자신의 {@code sourceType}이 보조 축이다. 파생 근거는 종류가 {@code
     * REPEATED_SUBJECT}·{@code LONGITUDINAL}이라 보조 축에 걸리지 않으므로 말단 참조만으로 결정된다.
     */
    private boolean hasChildExpression() {
      if (item.sourceType() != null && item.sourceType().isChildExpression()) {
        return true;
      }
      return leaves.stream()
          .anyMatch(leaf -> leaf.kind() != null && leaf.kind().isChildExpression());
    }
  }
}
