package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * JWT 인증기가 아직 연결되지 않은 운영 프로필에서 임시 Header 인증을 차단하는 안전 경계다.
 *
 * <p>Bearer 문자열을 검증하지 않고 보호자 ID로 사용하는 동작을 운영 인증으로 오인하지 않도록 항상 인증 실패를 반환한다.
 */
@Component
@Profile("!local & !test & !integration-test")
public class UnavailableProductionGuardianResolver implements GuardianUserResolver {

  /**
   * JWT 검증기 미연결 상태의 운영 요청을 거부한다.
   *
   * @param authorization 검증하지 않는 Authorization Header
   * @param guardianUserId 운영에서 사용하지 않는 임시 보호자 Header
   * @return 반환하지 않는다
   * @throws BusinessException 항상 정식 인증이 필요함을 알리는 경우
   */
  @Override
  public Long resolve(String authorization, String guardianUserId) {
    throw new BusinessException(ConversationStartErrorCode.UNAUTHORIZED);
  }
}
