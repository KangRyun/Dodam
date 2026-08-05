package com.ssafy.b209.report.safety;

import java.util.List;

/**
 * 안전 검증에 넣는 근거 항목 한 건이다(875 계약 §4 {@code evidenceItems[]}에 대응하는 중립 입력 타입).
 *
 * <p>저장 엔티티가 아니다. 이 이슈(S15P11B209-901)는 저장 구조와 독립적으로 검증 알고리즘을 완성하기 위해 자기 입력 타입을 정의하며, 저장 엔티티가 준비되면
 * 얇은 어댑터가 1:1로 매핑한다. 그래서 필드명·enum 값을 계약과 AI 응답 형태에 맞춰 두었다.
 *
 * <p><strong>배타 규칙:</strong> {@code sourceRef}와 {@code derivedFrom} 중 정확히 하나만 가진다. 둘 다 있거나 둘 다 없으면
 * 무효이며 {@link InterpretationExclusionReason#EVIDENCE_SOURCE_EXCLUSIVITY_VIOLATED}로 제외된다(875 계약 §4).
 * 저장 스키마는 이 규칙의 절반만 표현할 수 있다 — {@code report_evidence_items}의 {@code (source_ref_kind,
 * source_ref_id)} 쌍 CHECK는 "둘 다 있거나 둘 다 없음"만 강제하고, 파생 행의 존재 여부는 CHECK로 표현할 수 없다. 그 나머지 절반을 이 게이트가
 * 막는다.
 *
 * @param evidenceId 근거 식별자이며 카드의 {@code evidenceRefs}가 이 값을 가리킨다
 * @param sourceType 근거 종류이며 해석할 수 없으면 {@code null}
 * @param text 보호자에게 보여줄 근거 문장이며 없으면 {@code null}. 아이 표현이 섞일 수 있어 로그에 남기지 않는다
 * @param sourceRef 원본 근거의 참조이며 파생 근거면 {@code null}
 * @param derivedFrom 파생 근거가 펼쳐질 <strong>원본 참조 목록</strong>이며 원본 근거면 {@code null} 또는 빈 목록. {@code
 *     evidenceId} 참조가 아니라 {@link EvidenceSourceRef} 객체 목록이다 — AI({@code interpretation_gate.py}
 *     ·{@code internal_contracts.py})와 저장 모델({@code report_evidence_derivations}의 {@code
 *     (source_ref_kind, source_ref_id)} 행)이 모두 이 형태다
 * @param sttNeedsConfirmation 음성 인식 결과가 미확정이면 {@code true}. 문답 표시에는 남지만 근거로는 쓸 수 없다(보호자 계약 §4-4)
 * @param crisisReason 위기 사유이며 없으면 {@code null}. 값이 있으면 근거로 쓸 수 없다(보호자 계약 §4-4)
 */
public record EvidenceCandidate(
    Long evidenceId,
    EvidenceSourceType sourceType,
    String text,
    EvidenceSourceRef sourceRef,
    List<EvidenceSourceRef> derivedFrom,
    boolean sttNeedsConfirmation,
    EvidenceCrisisReason crisisReason) {

  /**
   * 원본 근거 한 건을 만든다.
   *
   * @param evidenceId 근거 식별자
   * @param sourceType 근거 종류
   * @param text 근거 문장이며 없으면 {@code null}
   * @param sourceRef 원본 참조
   * @return 원본 근거 항목
   */
  public static EvidenceCandidate source(
      Long evidenceId, EvidenceSourceType sourceType, String text, EvidenceSourceRef sourceRef) {
    return new EvidenceCandidate(evidenceId, sourceType, text, sourceRef, null, false, null);
  }

  /**
   * 다른 근거에서 파생된 근거 한 건을 만든다.
   *
   * @param evidenceId 근거 식별자
   * @param sourceType 근거 종류
   * @param text 근거 문장이며 없으면 {@code null}
   * @param derivedFrom 이 근거가 펼쳐질 원본 참조 목록
   * @return 파생 근거 항목
   */
  public static EvidenceCandidate derived(
      Long evidenceId,
      EvidenceSourceType sourceType,
      String text,
      List<EvidenceSourceRef> derivedFrom) {
    return new EvidenceCandidate(evidenceId, sourceType, text, null, derivedFrom, false, null);
  }

  /**
   * 이 근거가 다른 근거에서 파생되었는지 판단한다.
   *
   * @return {@code derivedFrom}에 하나 이상의 항목이 있으면 {@code true}
   */
  public boolean isDerived() {
    return derivedFrom != null && !derivedFrom.isEmpty();
  }

  /**
   * 근거로 사용할 수 없는 항목인지 판단한다.
   *
   * @return 미확정 음성 발화이거나 위기 사유가 붙어 있으면 {@code true}
   */
  public boolean isUnusableAsEvidence() {
    return sttNeedsConfirmation || crisisReason != null;
  }
}
