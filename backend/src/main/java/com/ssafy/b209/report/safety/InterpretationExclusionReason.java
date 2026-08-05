package com.ssafy.b209.report.safety;

/**
 * 구조적 공개 게이트가 카드를 <strong>제외</strong>한 사유다(보호자 계약 §4-3 1단).
 *
 * <p>이 사유들은 {@link com.ssafy.b209.report.domain.ReportFeatureVisibility#EXPERT_ONLY} 강등 사유가 아니다 —
 * 근거 자체가 없으므로 표현을 다듬어도 공개 대상이 아니다. 강등은 표현 안전 필터(2단)만 만들고 그 사유는 {@link
 * InterpretationDemotionReason}이 담는다. 두 실패의 성질이 달라 타입을 갈랐다.
 *
 * <p>이 enum 값은 로그에 남겨도 안전한 코드다. 카드 원문·아이 표현은 로그에 남기지 않는다.
 *
 * <p>저장 계층(S15P11B209-900)의 {@code report_public_interpretations.withheld_reason_code}가 {@code
 * VARCHAR(40)}이므로 이름 길이가 40자를 넘으면 어댑터에서 저장할 수 없다. 그 상한은 테스트로 고정한다.
 */
public enum InterpretationExclusionReason {
  /** 근거 참조가 아예 없다. */
  EVIDENCE_REF_MISSING,
  /** 근거 참조가 실존하는 {@code evidenceId}를 가리키지 않는다. */
  EVIDENCE_REF_UNRESOLVED,
  /** 한 근거가 {@code sourceRef}와 {@code derivedFrom}을 둘 다 갖거나 둘 다 갖지 않는다. */
  EVIDENCE_SOURCE_EXCLUSIVITY_VIOLATED,
  /** 말단 원본 참조를 해석할 수 없다. 조합키 형태 식별자도 여기에 해당한다. */
  EVIDENCE_SOURCE_REF_UNRESOLVABLE,
  /** 근거의 {@code sourceType}을 해석할 수 없다. */
  EVIDENCE_SOURCE_TYPE_UNKNOWN,
  /** 파생 전개가 순환한다. 전개 경로 집합으로 전개를 끊고 이 사유를 남긴다. */
  EVIDENCE_CYCLE_DETECTED,
  /** 미확정 음성 발화를 근거로 썼다(보호자 계약 §4-4). */
  EVIDENCE_STT_UNCONFIRMED,
  /** 위기 사유가 붙은 메시지를 근거로 썼다(보호자 계약 §4-4). */
  EVIDENCE_CRISIS_MESSAGE,
  /** 독립 근거가 2건 미만이다. */
  INDEPENDENT_EVIDENCE_INSUFFICIENT,
  /** 아이 표현 근거가 한 건도 없다. */
  CHILD_EXPRESSION_EVIDENCE_MISSING,
  /** {@code category}가 허용된 관찰 관점 라벨이 아니다. */
  CATEGORY_NOT_ALLOWED,
  /** {@code scopeText}가 비어 있다. */
  SCOPE_TEXT_MISSING,
  /** {@code homeObservationGuide}가 비어 있다. */
  HOME_OBSERVATION_GUIDE_MISSING,
  /** {@code tendencyText}가 비어 있다. */
  TENDENCY_TEXT_MISSING,
  /** {@code tendencyText}가 가능성 어조가 아니다. */
  TENDENCY_TEXT_NOT_POSSIBILITY_TONE
}
