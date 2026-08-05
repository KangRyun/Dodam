package com.ssafy.b209.report.domain;

/**
 * 경향 해석 카드의 공개 판정 결과다.
 *
 * <p>두 검사의 실패를 구분해 담는다(계약 §4-3). 구조적 공개 게이트 실패는 근거 자체가 없으므로 표현을 다듬어도 공개 대상이 아니고, 표현 안전 필터 실패는 내용에
 * 가치가 있어 전문가 검토로 돌린다. 두 실패를 한 상태로 묶으면 검토해도 공개할 수 없는 항목이 검토 대기열에 쌓인다.
 */
public enum ReportInterpretationDisclosureState {
  /** 구조 게이트와 표현 필터를 모두 통과해 보호자에게 노출한다. */
  PUBLISHED,
  /** 구조적 공개 게이트에서 탈락해 응답에서 제외한다. 강등이 아니다. */
  WITHHELD,
  /** 표현 안전 필터에서 걸려 전문가 검토로 돌린다. 내용은 보존한다. */
  EXPERT_ONLY;

  /**
   * 보호자 응답에 실어도 되는 상태인지 확인한다.
   *
   * @return 공개 가능하면 {@code true}
   */
  public boolean isGuardianVisible() {
    return this == PUBLISHED;
  }
}
