package com.ssafy.b209.auth.domain;

/**
 * 사용자 계정의 이용 상태를 나타낸다. 실제 탈퇴 처리는 사용자 행을 즉시 삭제한다.
 *
 * <p>상수 값은 {@code users.account_status}의 CHECK 제약과 정확히 일치해야 한다. V3 Migration이 제약을 {@code
 * ('PENDING','ACTIVE','SUSPENDED','DELETED')}로 변경하고 기존 {@code WITHDRAWN} 행을 {@code DELETED}로
 * 전환했으므로, Enum도 {@code DELETED}를 사용한다.
 */
public enum AccountStatus {
  /** OAuth 인증 후 Onboarding을 기다리는 상태이다. */
  PENDING,
  /** 정상적으로 서비스를 이용할 수 있는 상태이다. */
  ACTIVE,
  /** 운영 정책에 따라 일시적으로 이용이 제한된 상태이다. */
  SUSPENDED,
  /** 과거 데이터 호환을 위한 삭제 상태이며 신규 탈퇴는 즉시 삭제한다. */
  DELETED
}
