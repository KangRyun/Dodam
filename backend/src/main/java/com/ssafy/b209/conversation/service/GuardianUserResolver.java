package com.ssafy.b209.conversation.service;

/**
 * 외부 요청의 인증 정보에서 현재 보호자 식별자를 제공하는 경계다.
 *
 * <p>운영에서는 JWT를 검증하는 구현체가 이 경계를 제공해야 하며, 개발·테스트 프로필에서만 임시 Header 구현체를 사용한다.
 */
public interface GuardianUserResolver {

  /**
   * 인증 정보에서 현재 보호자 식별자를 해석한다.
   *
   * @param authorization 외부 Authorization Header
   * @param guardianUserId 개발·테스트 전용 임시 보호자 Header
   * @return 인증된 현재 보호자 식별자
   * @throws com.ssafy.b209.global.exception.BusinessException 인증 정보가 유효하지 않거나 운영 JWT 검증기가 준비되지 않은
   *     경우
   */
  Long resolve(String authorization, String guardianUserId);
}
