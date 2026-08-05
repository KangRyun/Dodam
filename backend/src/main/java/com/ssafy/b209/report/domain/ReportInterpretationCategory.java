package com.ssafy.b209.report.domain;

/**
 * 경향 해석 카드의 관찰 관점 라벨이다.
 *
 * <p>성격 분류가 아니라 "무엇을 관찰한 관점인가"를 나타낸다. 보호자 계약 §4-1 ③이 성격 분류 라벨을 금지하므로 이 목록을 늘릴 때도 특질 이름을 넣지 않는다.
 */
public enum ReportInterpretationCategory {
  /** 가족·또래와의 관계 관점이다. */
  RELATIONSHIP,
  /** 감정 표현 관점이다. */
  EMOTION,
  /** 자기 표현 방식 관점이다. */
  SELF_EXPRESSION,
  /** 활동을 풀어가는 방식 관점이다. */
  ACTIVITY_STYLE,
  /** 새로운 상황에 적응하는 모습 관점이다. */
  ADAPTATION
}
