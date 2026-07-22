package com.ssafy.b209.conversation.service;

import com.ssafy.b209.auth.filter.AuthFilterProperties;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/**
 * 검증된 Access Token Principal에서 보호자 식별자를 읽고 테스트 전환 기간의 임시 Header를 제한적으로 지원한다.
 *
 * <p>운영 기본값에서는 {@code X-Guardian-User-Id}를 신뢰하지 않는다. 임시 Header 경로는 기존 Controller 테스트를 단계적으로 전환하기 위한
 * Test Profile에서만 활성화한다.
 */
@Component
public class TemporaryGuardianResolver implements GuardianUserResolver {

  private final AuthFilterProperties properties;

  /**
   * 보호자 식별자 Resolver를 구성한다.
   *
   * @param properties 임시 Header 허용 여부
   */
  public TemporaryGuardianResolver(AuthFilterProperties properties) {
    this.properties = properties;
  }

  /**
   * 검증된 Access Token Principal에서 보호자 식별자를 읽는다.
   *
   * @param authorization Test Profile의 기존 요청이 전달하는 임시 Authorization Header
   * @param guardianUserId Test Profile의 기존 요청이 전달하는 임시 보호자 ID Header
   * @return Access Token Subject의 사용자 ID
   * @throws BusinessException 인증 Principal이 없고 임시 Header도 허용되지 않은 경우
   */
  @Override
  public Long resolve(String authorization, String guardianUserId) {
    Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
    if (authentication != null && authentication.getPrincipal() instanceof AuthenticatedUser user) {
      return user.userId();
    }
    if (!properties.legacyHeaderEnabled()) {
      throw new BusinessException(ConversationStartErrorCode.UNAUTHORIZED);
    }
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
