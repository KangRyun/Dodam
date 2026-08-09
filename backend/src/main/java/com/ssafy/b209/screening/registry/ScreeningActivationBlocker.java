package com.ssafy.b209.screening.registry;

/**
 * 도구를 켜지 못하게 막고 있는 사유다.
 *
 * <p>문구가 아니라 값으로 둔 이유가 있다. 사유를 문장으로만 적어 두면 상태 판정이 문자열 매칭이 되고, 등록부 문구를 다듬는 순간 판정이 조용히 바뀐다. 무엇이 막고
 * 있는지는 <strong>사람이 읽는 설명과 별개로</strong> 코드가 알아야 한다.
 */
public enum ScreeningActivationBlocker {
  /** 문항·전자화·상업 이용·자동 채점·결과 재표시 권한이 없다. 저작권자와의 계약 문제라 코드로 우회할 수 없다. */
  LICENSE,

  /** 한국 적용 기준·절단점·결과 문구에 대한 임상 책임자 승인이 없다. */
  CLINICAL_APPROVAL,

  /** 양성 즉시 대응·야간/주말 경로 등 임상 운영 주체가 없다. 위기 도구가 여기에 해당한다. */
  CLINICAL_OPERATIONS
}
