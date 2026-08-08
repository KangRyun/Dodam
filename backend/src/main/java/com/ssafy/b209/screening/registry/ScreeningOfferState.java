package com.ssafy.b209.screening.registry;

/**
 * 한 아동에게 그 도구를 지금 제공할 수 있는지에 대한 판정이다.
 *
 * <p>이 값은 <strong>결정론적 코드가 정한다.</strong> LLM 은 도구를 켜지도, 제안하지도, 채점하지도 않는다 — 모델에게 맡기면 그림 한 장을 근거로 검사를
 * 권하게 된다.
 */
public enum ScreeningOfferState {
  /** 아이 나이가 그 도구의 공식 적용 연령 밖이다. */
  NOT_ELIGIBLE_BY_AGE,

  /** 제공하지 않는다. 나이를 모를 때도 여기로 온다 — 모르면 제안하지 않는다. */
  NOT_OFFERED,

  /** 제공할 수 있으며 보호자 별도 동의만 남았다. */
  OFFERABLE_AFTER_CONSENT,

  /** 문항·전자화·채점 라이선스가 없어 제공할 수 없다. */
  PENDING_LICENSE,

  /** 임상 승인 또는 임상 운영 체계가 없어 제공할 수 없다. */
  PENDING_CLINICAL_APPROVAL,

  /** 외부에서 받은 결과가 이미 기록돼 있다. */
  EXTERNAL_RESULT_AVAILABLE,

  /** 공식 서비스에서 확인된 결과가 있다. 지금은 공식 연동이 없어 나오지 않는다. */
  COMPLETED_OFFICIAL_RESULT,

  /** 후속 평가가 권고된 상태다. */
  FOLLOWUP_RECOMMENDED,

  /** 위기 대응이 우선인 상태다. 이때는 선별이 아니라 안전 절차가 먼저다. */
  CRISIS_PATHWAY_ACTIVE
}
