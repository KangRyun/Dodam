package com.ssafy.b209.report.safety;

import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import java.util.List;
import java.util.Set;

/**
 * 경향 해석 안전 검증 2단을 모두 거친 결과다.
 *
 * <p>세 갈래는 처리 성질이 서로 다르다.
 *
 * <ul>
 *   <li>{@code published} — 두 단을 통과해 보호자에게 공개할 수 있는 카드
 *   <li>{@code excluded} — 1단 실패. <strong>미공개(제외)</strong>이며 강등이 아니다. 노출 범위 값 자체를 갖지 않는다
 *   <li>{@code demoted} — 2단 실패. <strong>EXPERT_ONLY 강등</strong>이며 내용은 보존된다
 * </ul>
 *
 * <p>저장 계층(S15P11B209-900)의 {@code report_public_interpretations}에 그대로 대응한다. 어댑터가 참고할 표다.
 *
 * <table border="1">
 *   <caption>결과 갈래 ↔ 저장 컬럼</caption>
 *   <tr><th>이 결과<th>{@code disclosure_state}<th>{@code withheld_reason_code}
 *   <tr><td>{@link #published()}<td>{@code PUBLISHED}<td>{@code NULL}
 *   <tr><td>{@link #excluded()}<td>{@code WITHHELD}<td>{@link ExcludedInterpretation#reasons()}의 첫 원소
 *   <tr><td>{@link #demoted()}<td>{@code EXPERT_ONLY}<td>{@link DemotedInterpretation#reason()}
 * </table>
 *
 * <p>{@code withheld_reason_code}는 한 칸뿐이고 {@code disclosure_state <> 'PUBLISHED'}면 NOT NULL을
 * 요구한다(V37). 제외는 사유가 여러 건 겹칠 수 있으므로 {@code reasons()}의 순회 순서가 고정돼 있어야 한다 — {@link
 * ExcludedInterpretation#reasons()} 문서를 참고한다.
 *
 * <p><strong>한계(S15P11B209-901 범위):</strong> 이 타입은 검증 결과를 <em>도메인 반환값</em>으로만 표현한다. 저장·응답 조립·PDF
 * 노출은 이 이슈 범위가 아니므로, "게이트 통과 0건이면 공개 목록이 빈 컬렉션이고 예외가 아니다"(875 계약 §10)도 API 응답이 아니라 {@link
 * #published()}가 빈 목록임을 통해서만 고정된다. 응답·PDF 단계의 빈 배열 보장은 저장·조립 이슈에서 다시 검증해야 한다.
 *
 * @param published 공개 가능한 카드 목록이며 없으면 빈 목록
 * @param excluded 1단에서 제외된 카드 목록이며 없으면 빈 목록
 * @param demoted 2단에서 강등된 카드 목록이며 없으면 빈 목록
 */
public record InterpretationSafetyOutcome(
    List<PublishedInterpretation> published,
    List<ExcludedInterpretation> excluded,
    List<DemotedInterpretation> demoted) {

  /**
   * 리포트 초안을 전문가 검토 대상으로 올려야 하는지 판단한다.
   *
   * <p>1단 제외는 검토 대상이 아니다 — 근거가 없어 공개하지 않는 것이고, 전문가가 표현을 다듬어 해결할 문제가 아니다.
   *
   * @return 강등된 카드가 하나라도 있으면 {@code true}
   */
  public boolean expertReviewRequired() {
    return !demoted.isEmpty();
  }

  /**
   * 두 단을 통과한 카드다.
   *
   * @param sourceIndex 입력 목록에서의 0부터 시작하는 위치
   * @param candidate 통과한 카드 원본
   * @param independentEvidenceCount 병합 상한을 적용한 뒤 센 독립 근거 수
   */
  public record PublishedInterpretation(
      int sourceIndex, InterpretationCandidate candidate, int independentEvidenceCount) {}

  /**
   * 1단에서 제외된 카드다.
   *
   * <p>노출 범위 값을 갖지 않는다. 이 카드는 어디에도 실리지 않으며 전문가 검토 대상도 아니다.
   *
   * @param sourceIndex 입력 목록에서의 0부터 시작하는 위치
   * @param candidate 제외된 카드 원본
   * @param reasons 제외 사유 집합이며 비어 있지 않다. {@link java.util.EnumSet} 기반이라 <strong>순회 순서가 {@link
   *     InterpretationExclusionReason}의 선언 순서로 고정</strong>된다 — 사유 코드를 한 칸만 담는 저장 컬럼({@code
   *     withheld_reason_code})에 넣어야 할 때 첫 원소를 결정적으로 고를 수 있다
   */
  public record ExcludedInterpretation(
      int sourceIndex,
      InterpretationCandidate candidate,
      Set<InterpretationExclusionReason> reasons) {}

  /**
   * 2단에서 강등된 카드다. 내용은 보존된다.
   *
   * @param sourceIndex 입력 목록에서의 0부터 시작하는 위치
   * @param candidate 강등된 카드 원본이며 내용을 그대로 보존한다
   * @param matchedPatterns 매칭된 패턴 문자열 목록이며 원문 조각은 담지 않는다. <strong>로그·진단 전용이고 저장 대상이 아니다</strong> —
   *     사유 코드 컬럼에 넣을 값은 {@link #reason()}이다. 패턴은 검출기 내부 표현이라 컬럼의 의미를 흐리고 길이 상한도 보장되지 않는다
   */
  public record DemotedInterpretation(
      int sourceIndex, InterpretationCandidate candidate, List<String> matchedPatterns) {

    /**
     * 강등 사유 코드다.
     *
     * <p>저장 계층의 {@code withheld_reason_code}에 넣을 값이다. {@code disclosure_state <> 'PUBLISHED'}면 NOT
     * NULL을 요구하는 CHECK가 있어(V37) 강등에도 코드가 반드시 필요하다. 필드가 아니라 상수를 돌려주는 메서드로 둔 이유는 <strong>값이 비어 있는 강등
     * 결과를 만들 수 없게</strong> 하려는 것이다 — 조립부가 코드를 채우는 것을 잊을 자리가 없다.
     *
     * @return 항상 {@link InterpretationDemotionReason#EXPRESSION_FILTER_BLOCKED}
     */
    public InterpretationDemotionReason reason() {
      return InterpretationDemotionReason.EXPRESSION_FILTER_BLOCKED;
    }

    /**
     * 강등된 카드의 노출 범위다.
     *
     * <p>기존 도메인 enum 값을 재사용하지만, 이는 {@code ObservationReportPersistenceService.resolveVisibility()}
     * 경로를 타는 것과 무관하다(보호자 계약 §4-2 결정 1). 여기서는 "노출 범위"라는 값만 공유하며 판단은 이 검증기가 직접 한다.
     *
     * @return 항상 {@link ReportFeatureVisibility#EXPERT_ONLY}
     */
    public ReportFeatureVisibility visibility() {
      return ReportFeatureVisibility.EXPERT_ONLY;
    }
  }
}
