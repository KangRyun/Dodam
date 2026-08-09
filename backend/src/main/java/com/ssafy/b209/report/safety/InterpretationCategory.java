package com.ssafy.b209.report.safety;

/**
 * 경향 해석 카드가 가질 수 있는 관찰 관점 라벨이다.
 *
 * <p>성격 분류가 아니라 "무엇을 관찰한 결과인지"를 나타내는 라벨만 허용한다(보호자 계약 §4-1 조건 3, 875 계약 §3). 여기에 없는 값은 구조적 공개 게이트에서
 * {@link InterpretationExclusionReason#CATEGORY_NOT_ALLOWED}로 제외한다.
 */
public enum InterpretationCategory {
  /** 가족·또래 등 관계 관점에서 관찰한 경향이다. */
  RELATIONSHIP,
  /** 감정 표현 관점에서 관찰한 경향이다. */
  EMOTION,
  /** 자기 표현 방식 관점에서 관찰한 경향이다. */
  SELF_EXPRESSION,
  /** 활동을 수행하는 방식 관점에서 관찰한 경향이다. */
  ACTIVITY_STYLE,
  /** 새로운 상황에 적응하는 방식 관점에서 관찰한 경향이다. */
  ADAPTATION;

  /**
   * 계약 코드값을 라벨로 해석한다.
   *
   * <p>해석하지 못한 값을 예외로 던지지 않고 {@code null}로 돌려주는 이유는, 알 수 없는 라벨 하나가 리포트 전체를 실패시키면 안 되고 해당 카드만 제외해야
   * 하기 때문이다(875 계약 §4-2 "문제 항목만 제외").
   *
   * @param code 계약 코드값이며 없으면 {@code null}
   * @return 해석된 라벨이며 해석할 수 없으면 {@code null}
   */
  public static InterpretationCategory fromCode(String code) {
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
