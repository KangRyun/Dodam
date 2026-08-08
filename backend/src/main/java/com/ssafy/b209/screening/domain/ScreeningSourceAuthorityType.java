package com.ssafy.b209.screening.domain;

/**
 * 결과를 발급한 곳의 성격이다.
 *
 * <p><strong>지금 들어오는 값은 사실상 {@link #GUARDIAN_REPORTED} 하나다.</strong> 공식 서비스 연동이 없어 보호자가 결과지를 보고 옮겨
 * 적기 때문이다 — 그래서 화면은 이 기록을 공식 결과로 표시하지 않는다.
 */
public enum ScreeningSourceAuthorityType {
  /** 공식 서비스에서 직접 받아온 결과다. 연동이 생기기 전에는 쓰이지 않는다. */
  OFFICIAL_SERVICE,

  /** 보호자가 결과지를 보고 옮겨 적었다. 검증되지 않은 값이다. */
  GUARDIAN_REPORTED,

  /** 임상가가 전달한 결과다. */
  CLINICIAN_REPORTED
}
