package com.ssafy.b209.auth.domain;

/** 서비스가 신뢰하는 OAuth Provider를 나타낸다. 자체 로그인은 지원하지 않는다. */
public enum AuthProvider {
  /** Kakao Login이 보증한 계정이다. */
  KAKAO,
  /** Google OpenID Connect가 보증한 계정이다. */
  GOOGLE,
  /** Naver Login이 보증한 계정이다. */
  NAVER,
  /** Sign in with Apple이 보증한 계정이다. */
  APPLE
}
