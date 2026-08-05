package com.ssafy.b209.report.safety;

/**
 * 근거 원본이 어느 레코드에서 왔는지 나타낸다(875 계약 §4 {@code sourceRef.kind}).
 *
 * <p>각 종류의 {@code id}는 <strong>BE가 발급한 식별자</strong>여야 한다. 조합키를 허용하면 AI가 값을 조립할 수 있어 검증이 무의미해진다.
 */
public enum EvidenceSourceKind {
  /** 답변 메시지 식별자다. */
  QA_ANSWER,
  /** 탐지 객체 행 식별자다. */
  DETECTED_OBJECT,
  /** {@code analysis_observation_results} 행 식별자다. */
  VLM_OBSERVATION,
  /** {@code drawing_session_emotions} 행 식별자다. */
  EMOTION_SELECTION,
  /** BE가 발급한 지표 스냅샷 식별자다. */
  ACTIVITY_METRIC,
  /**
   * 이전 활동의 원본 관찰 레코드 또는 확인된 아동 표현 메시지 식별자다.
   *
   * <p>이전 AI 해석 결과를 가리키면 자기 해석이 자기 근거가 되는 순환 추론이 된다(875 계약 §4). 어떤 행을 가리키는지는 이 게이트가 아니라 근거를 만드는 쪽에서
   * 보장한다 — 여기서는 식별자 형태만 검증한다.
   */
  PRIOR_ACTIVITY;

  /**
   * 아이 자신의 표현이 담긴 원본인지 판단한다.
   *
   * <p><strong>아이 표현 요건은 이 축으로 판정한다.</strong> 파생 근거를 펼치면 남는 것은 원본 참조뿐이고 그 원본의 {@code sourceType}은
   * 근거 풀에 없을 수 있다 — 참조가 가리키는 행이 근거 항목으로 실려 있지 않아도 참조 자체는 유효하기 때문이다. 그래서 판정 축을 종류가 아니라 <strong>말단
   * 참조의 {@code kind}</strong>로 둔다({@code ai/interpretation_gate.py}의 {@code
   * CHILD_EXPRESSION_REF_KINDS}와 같은 집합).
   *
   * @return 아이 답변 메시지({@link #QA_ANSWER})나 아이가 고른 감정({@link #EMOTION_SELECTION})이면 {@code true}
   */
  public boolean isChildExpression() {
    return this == QA_ANSWER || this == EMOTION_SELECTION;
  }

  /**
   * 계약 코드값을 원본 종류로 해석한다.
   *
   * @param code 계약 코드값이며 없으면 {@code null}
   * @return 해석된 원본 종류이며 해석할 수 없으면 {@code null}
   */
  public static EvidenceSourceKind fromCode(String code) {
    if (code == null || code.isBlank()) {
      return null;
    }
    try {
      return valueOf(code.trim());
    } catch (IllegalArgumentException exception) {
      return null;
    }
  }
}
