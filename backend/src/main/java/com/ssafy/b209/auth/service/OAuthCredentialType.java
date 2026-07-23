package com.ssafy.b209.auth.service;

/** 모바일 OAuth 로그인에서 Provider에 따라 검증할 Token 종류를 구분한다. */
public enum OAuthCredentialType {
  /** Kakao·Naver 사용자 API 호출에 사용하는 Provider Access Token이다. */
  ACCESS_TOKEN,

  /** Google 공개키로 서명과 Claim을 검증하는 ID Token이다. */
  ID_TOKEN
}
