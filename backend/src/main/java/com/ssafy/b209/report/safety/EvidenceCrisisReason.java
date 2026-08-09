package com.ssafy.b209.report.safety;

/**
 * 근거로 쓸 수 없는 위기 사유다(보호자 계약 §4-4, 875 계약 §6-1).
 *
 * <p>위기 사유가 붙은 메시지는 문답 표시에서 제외되고 <strong>근거·독립 근거 계수에서도 제외</strong>된다. 이 값이 붙은 항목이 근거로 실려 있으면 구조적
 * 공개 게이트가 해당 카드를 제외한다.
 */
public enum EvidenceCrisisReason {
  /** 자기 위해 위험 신호다. */
  SELF_HARM_RISK,
  /** 학대 정황 진술이다. 가해자가 보호자일 수 있어 보호자 자동 통지를 만들지 않는다. */
  ABUSE_DISCLOSURE,
  /** 위기 의도 표현이다. */
  CRISIS_INTENT;

  /**
   * 계약 코드값을 위기 사유로 해석한다.
   *
   * @param code 계약 코드값이며 없으면 {@code null}
   * @return 해석된 위기 사유이며 해석할 수 없으면 {@code null}
   */
  public static EvidenceCrisisReason fromCode(String code) {
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
