package com.ssafy.b209.auth.service;

/**
 * Google ID Token의 서명과 Claim을 검증해 서비스에서 사용할 불변 사용자 신원으로 변환한다.
 *
 * <p>구현체는 검증 전 Payload를 신뢰해서는 안 되며 Token 원문을 저장하거나 로그에 기록하지 않는다.
 */
public interface GoogleIdTokenVerifier {

  /**
   * Google ID Token을 검증한다.
   *
   * @param idToken 모바일 Google 로그인 SDK가 발급한 ID Token
   * @return 서명과 필수 Claim 검증을 마친 Google 사용자 신원
   */
  VerifiedOAuthIdentity verify(String idToken);
}
