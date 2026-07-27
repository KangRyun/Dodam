package com.ssafy.b209.auth.service;

/**
 * Apple Identity Token의 서명과 Claim을 검증해 서비스에서 사용할 불변 사용자 신원으로 변환한다.
 *
 * <p>구현체는 검증 전 Payload를 신뢰해서는 안 되며 Token과 raw nonce 원문을 저장하거나 로그에 기록하지 않는다.
 */
public interface AppleIdTokenVerifier {

  /**
   * Apple Identity Token과 로그인 요청 전에 생성한 raw nonce를 검증한다.
   *
   * @param idToken Sign in with Apple이 발급한 Identity Token
   * @param rawNonce Apple 인증 요청 전에 앱이 생성한 원본 nonce
   * @return 서명과 필수 Claim 검증을 마친 Apple 사용자 신원
   */
  VerifiedOAuthIdentity verify(String idToken, String rawNonce);
}
