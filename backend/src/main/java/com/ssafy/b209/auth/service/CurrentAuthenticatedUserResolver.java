package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/** 검증된 Access Token이 설정한 SecurityContext에서 현재 서비스 사용자 ID를 제공한다. */
@Component
public class CurrentAuthenticatedUserResolver {

  /** 상태를 보관하지 않는 현재 사용자 Resolver를 생성한다. */
  public CurrentAuthenticatedUserResolver() {}

  /**
   * 현재 요청의 검증된 사용자 ID를 반환한다.
   *
   * @return Access Token Subject에서 복원한 사용자 ID
   * @throws BusinessException 인증 Principal이 없거나 예상 타입이 아닌 경우
   */
  public Long requireUserId() {
    Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
    if (authentication != null && authentication.getPrincipal() instanceof AuthenticatedUser user) {
      return user.userId();
    }
    throw new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED);
  }
}
