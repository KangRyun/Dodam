package com.ssafy.b209.auth.domain;

/** Onboarding에서 확정되는 사용자 역할을 나타낸다. */
public enum UserRole {
  /** 아동의 활동을 관리하는 보호자이다. */
  GUARDIAN,
  /** 권한을 부여받아 분석 결과를 확인하는 전문가이다. */
  EXPERT,
  /** 서비스 운영 관리자이다. */
  ADMIN
}
