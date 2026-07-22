package com.ssafy.b209.consent.domain;

/** 변경하지 않는 동의 이력에 기록할 사용자의 의사 표시다. */
public enum ConsentAction {
  /** 약관에 동의했다. */
  AGREE,
  /** 기존 동의를 철회하거나 선택 약관에 동의하지 않았다. */
  WITHDRAW
}
