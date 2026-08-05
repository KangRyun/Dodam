package com.ssafy.b209.report.safety;

import com.ssafy.b209.report.safety.InterpretationSafetyOutcome.DemotedInterpretation;
import com.ssafy.b209.report.safety.InterpretationSafetyOutcome.ExcludedInterpretation;
import com.ssafy.b209.report.safety.InterpretationSafetyOutcome.PublishedInterpretation;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 경향 해석 카드에 안전 검증 2단을 순서대로 적용한다(보호자 계약 §4-3, 875 계약 §4-2).
 *
 * <p><strong>1단(구조적 공개 게이트)을 먼저</strong> 돌리고 통과분만 2단(표현 안전 필터)에 넣는다. 1단이 값싼 결정적 검사이기 때문이다. 리포트 전체를
 * 실패시키지 않고 문제 항목만 제외·강등한다.
 *
 * <p>실패 처리의 성질이 다르다 — 1단 실패는 <strong>미공개(제외)</strong>, 2단 실패는 <strong>EXPERT_ONLY 강등 + 전문가 검토
 * 필요</strong>다. 두 갈래를 {@link InterpretationSafetyOutcome}에서 서로 다른 목록으로 돌려주므로 호출부가 섞어 처리할 수 없다.
 *
 * <p><strong>범위(S15P11B209-901):</strong> 순수 도메인 로직이다. 저장·응답 노출·PDF 반영은 이 이슈 범위가 아니며, 저장 엔티티가 준비되면
 * 얇은 어댑터가 {@link InterpretationCandidate}·{@link EvidenceCandidate}로 매핑해 이 검증기를 호출한다. Spring 빈으로
 * 등록하지 않은 것도 같은 이유다 — 사용 지점이 정해질 때 배선한다.
 *
 * <p><strong>로그 가드레일:</strong> 카드 위치와 사유 코드·패턴만 남기고 카드 원문은 남기지 않는다. 카드 문장에는 아이 표현이 섞일 수 있다.
 */
public final class InterpretationSafetyVerifier {

  private static final Logger log = LoggerFactory.getLogger(InterpretationSafetyVerifier.class);

  private final InterpretationPublicationGate publicationGate;
  private final InterpretationExpressionFilter expressionFilter;

  /** 기본 게이트·필터를 쓰는 검증기를 만든다. */
  public InterpretationSafetyVerifier() {
    this(new InterpretationPublicationGate(), new InterpretationExpressionFilter());
  }

  /**
   * 게이트와 필터를 주입해 검증기를 만든다.
   *
   * @param publicationGate 1단 구조적 공개 게이트
   * @param expressionFilter 2단 표현 안전 필터
   */
  public InterpretationSafetyVerifier(
      InterpretationPublicationGate publicationGate,
      InterpretationExpressionFilter expressionFilter) {
    this.publicationGate = publicationGate;
    this.expressionFilter = expressionFilter;
  }

  /**
   * 카드 목록에 2단 검증을 적용한다.
   *
   * @param candidates 검증할 경향 해석 카드 목록이며 없으면 {@code null}
   * @param evidenceItems 근거 풀이며 없으면 {@code null}
   * @return 공개·제외·강등으로 나뉜 결과이며 입력이 비어 있으면 세 목록 모두 빈 목록
   */
  public InterpretationSafetyOutcome verify(
      List<InterpretationCandidate> candidates, List<EvidenceCandidate> evidenceItems) {
    Map<Long, EvidenceCandidate> pool = toPool(evidenceItems);
    List<PublishedInterpretation> published = new ArrayList<>();
    List<ExcludedInterpretation> excluded = new ArrayList<>();
    List<DemotedInterpretation> demoted = new ArrayList<>();

    List<InterpretationCandidate> input = candidates == null ? List.of() : candidates;
    for (int index = 0; index < input.size(); index++) {
      InterpretationCandidate candidate = input.get(index);
      if (candidate == null) {
        continue;
      }

      InterpretationPublicationGate.Decision decision = publicationGate.inspect(candidate, pool);
      if (!decision.passed()) {
        log.info("경향 해석 카드를 미공개 처리했다. index={}, reasons={}", index, decision.reasons());
        excluded.add(new ExcludedInterpretation(index, candidate, decision.reasons()));
        continue;
      }

      ExpressionVerdict verdict = expressionFilter.inspect(candidate);
      if (!verdict.safe()) {
        log.info(
            "경향 해석 카드를 전문가 검토로 강등했다. index={}, matchedPatterns={}",
            index,
            verdict.matchedPatterns());
        demoted.add(new DemotedInterpretation(index, candidate, verdict.matchedPatterns()));
        continue;
      }

      published.add(
          new PublishedInterpretation(index, candidate, decision.independentEvidenceCount()));
    }

    return new InterpretationSafetyOutcome(
        List.copyOf(published), List.copyOf(excluded), List.copyOf(demoted));
  }

  private static Map<Long, EvidenceCandidate> toPool(List<EvidenceCandidate> evidenceItems) {
    if (evidenceItems == null || evidenceItems.isEmpty()) {
      return Map.of();
    }
    Map<Long, EvidenceCandidate> pool = new LinkedHashMap<>();
    for (EvidenceCandidate item : evidenceItems) {
      if (item == null || item.evidenceId() == null) {
        continue;
      }
      // 같은 evidenceId가 중복으로 오면 먼저 온 항목을 남긴다 — 나중 항목이 앞선 항목의 검증 결과를 덮지 못하게 한다.
      pool.putIfAbsent(item.evidenceId(), item);
    }
    return pool;
  }
}
