package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;

/** OAuth authorization code를 Provider에서 검증하고 불변 사용자 식별자로 변환한다. */
public interface OAuthProviderClient {

  /**
   * authorization code를 Provider Token으로 교환한 뒤 사용자 신원을 조회한다.
   *
   * @param provider code를 발급한 OAuth Provider
   * @param request authorization code와 동일한 Redirect URI를 포함한 요청
   * @return Provider 응답 검증을 마친 사용자 신원
   */
  VerifiedOAuthIdentity verify(AuthProvider provider, OAuthLoginRequest request);
}
