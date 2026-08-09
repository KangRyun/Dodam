package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AuthProvider;

/** OAuth Provider Token을 검증하고 불변 사용자 식별자로 변환한다. */
public interface OAuthProviderClient {

  /**
   * Provider에 맞는 Token을 검증한 뒤 사용자 신원을 조회한다.
   *
   * @param provider Token을 발급한 OAuth Provider
   * @param credential 검증할 Token 종류와 원본 값
   * @return Provider 응답 검증을 마친 사용자 신원
   */
  VerifiedOAuthIdentity verify(AuthProvider provider, OAuthProviderCredential credential);
}
