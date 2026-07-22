package com.ssafy.b209.consent.domain;

/** 동의가 사용자 본인과 연결 아동 중 누구에게 적용되는지 나타낸다. */
public enum ConsentTargetScope {
  /** 사용자 본인 대상 약관이다. */
  USER,
  /** 연결된 특정 아동 대상 약관이다. */
  CHILD
}
