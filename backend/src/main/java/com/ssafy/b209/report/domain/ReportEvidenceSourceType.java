package com.ssafy.b209.report.domain;

/**
 * 근거가 어떤 종류의 관찰에서 왔는지 나타낸다.
 *
 * <p>화면에는 코드가 아니라 라벨만 노출한다(계약 §4). 독립 근거 개수는 이 종류가 아니라 원본 참조({@code sourceRef}) 단위로 센다 — 같은 답변 하나를
 * 두 종류로 신고해 2건을 만드는 것을 막기 위해서다.
 */
public enum ReportEvidenceSourceType {
  /** 그림에서 확인된 내용이다. */
  VISION,
  /** 아이의 답변이다. */
  CHILD_ANSWER,
  /** 아이가 선택한 감정이다. */
  SELECTED_EMOTION,
  /** 아이가 말한 감정이다. */
  STATED_EMOTION,
  /** 활동 기록 지표다. */
  ACTIVITY_METRIC,
  /** 여러 그림에서 반복된 파생 근거다. */
  REPEATED_SUBJECT,
  /** 이전 활동에서도 반복된 파생 근거다. */
  LONGITUDINAL;

  /**
   * 아이 자신의 표현에서 나온 근거인지 확인한다.
   *
   * @return 아이 답변·선택 감정·말한 감정이면 {@code true}
   */
  public boolean isChildExpression() {
    return this == CHILD_ANSWER || this == SELECTED_EMOTION || this == STATED_EMOTION;
  }

  /**
   * 다른 근거에서 파생된 종류인지 확인한다.
   *
   * @return 반복·추이 근거면 {@code true}
   */
  public boolean isDerived() {
    return this == REPEATED_SUBJECT || this == LONGITUDINAL;
  }
}
