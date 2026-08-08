package com.ssafy.b209.screening.registry;

/**
 * 표준화 선별도구의 런타임 활성 상태다.
 *
 * <p><strong>기본값은 {@link #DISABLED} 이며, 켜는 것은 코드 변경이 아니라 승인 절차다.</strong> 도구 하나를 켜려면 한국어판 타당화·정확한
 * 적용 연령·공식 매뉴얼·상업/전자화/자동채점 라이선스·양성 후 진료 경로·보호자 별도 동의·개인정보 영향평가가 모두 확인되고, 임상 책임자와 법무의 승인 ID가 남아야 한다.
 */
public enum ScreeningInstrumentState {
  /** 승인 절차가 끝나지 않아 제공하지 않는다. 등록부의 모든 도구가 현재 이 상태다. */
  DISABLED,

  /** 승인 절차가 끝나 제공할 수 있다. 아직 이 상태인 도구는 없다. */
  ENABLED
}
