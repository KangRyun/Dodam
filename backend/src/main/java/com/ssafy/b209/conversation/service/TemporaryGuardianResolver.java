package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.stereotype.Component;

/**
 * 정식 JWT 인증 도입 전 {@code X-Guardian-User-Id}에서 보호자 식별자를 읽는 임시 경계다.
 *
 * <p>Bearer 토큰의 실제 검증은 수행하지 않으므로 정식 인증 구현과 함께 반드시 교체해야 한다.
 */
@Component
public class TemporaryGuardianResolver {

  /**
   * 임시 Header와 Bearer 형식으로부터 보호자 식별자를 읽는다.
   *
   * @param authorization Bearer 형식만 점검하는 임시 Authorization Header
   * @param guardianUserId 임시 보호자 사용자 ID Header
   * @return 양의 보호자 사용자 ID
   * @throws BusinessException Header가 누락되었거나 유효하지 않은 경우
   */
  public Long resolve(String authorization, String guardianUserId) {
    if (authorization == null
        || !authorization.startsWith("Bearer ")
        || authorization.length() <= 7) {
      throw new BusinessException(ConversationStartErrorCode.UNAUTHORIZED);
    }
    try {
      long resolved = Long.parseLong(guardianUserId);
      if (resolved <= 0) throw new NumberFormatException();
      return resolved;
    } catch (RuntimeException exception) {
      throw new BusinessException(ConversationStartErrorCode.UNAUTHORIZED);
    }
  }
}
