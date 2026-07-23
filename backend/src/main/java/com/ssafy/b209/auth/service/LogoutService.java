package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.dto.request.LogoutRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.token.JwtRefreshTokenDecoder;
import com.ssafy.b209.auth.token.RefreshTokenHasher;
import com.ssafy.b209.auth.token.VerifiedRefreshToken;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.dao.DataAccessException;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.stereotype.Service;

/**
 * 인증된 사용자의 현재 기기 Refresh Token 세션을 검증하고 폐기하는 로그아웃 Use Case다.
 *
 * <p>Access Token은 상태를 저장하지 않으므로 즉시 폐기하지 않으며, 클라이언트가 로컬 Token을 제거한 뒤 남은 유효 시간 동안만 만료를 기다린다.
 */
@Service
public class LogoutService {

  private final JwtRefreshTokenDecoder tokenDecoder;
  private final RefreshTokenHasher tokenHasher;
  private final RefreshTokenSessionStore sessionStore;
  private final CurrentAuthenticatedUserResolver currentUserResolver;

  /**
   * 로그아웃 Service를 구성한다.
   *
   * @param tokenDecoder Refresh JWT 검증기
   * @param tokenHasher Redis 비교용 Token hash 계산기
   * @param sessionStore Refresh Token 세션 저장소
   * @param currentUserResolver Access Token 인증 사용자 확인 도구
   */
  public LogoutService(
      JwtRefreshTokenDecoder tokenDecoder,
      RefreshTokenHasher tokenHasher,
      RefreshTokenSessionStore sessionStore,
      CurrentAuthenticatedUserResolver currentUserResolver) {
    this.tokenDecoder = tokenDecoder;
    this.tokenHasher = tokenHasher;
    this.sessionStore = sessionStore;
    this.currentUserResolver = currentUserResolver;
  }

  /**
   * Access Token 사용자와 Refresh Token 사용자·기기·hash가 모두 일치하는 세션을 폐기한다.
   *
   * @param request 현재 기기의 Refresh Token과 기기 식별자
   * @throws BusinessException Refresh Token 또는 Redis 세션이 유효하지 않거나 저장소를 사용할 수 없는 경우
   */
  public void logout(LogoutRequest request) {
    Long authenticatedUserId = currentUserResolver.requireUserId();
    VerifiedRefreshToken verified = decode(request.refreshToken());
    if (!authenticatedUserId.equals(verified.userId())) {
      throw new BusinessException(AuthErrorCode.REFRESH_TOKEN_INVALID);
    }

    boolean revoked;
    try {
      revoked =
          sessionStore.revoke(
              verified.familyId(),
              authenticatedUserId,
              request.deviceId(),
              tokenHasher.hash(request.refreshToken()));
    } catch (DataAccessException exception) {
      throw new BusinessException(AuthErrorCode.AUTH_SESSION_UNAVAILABLE, exception);
    }
    if (!revoked) {
      throw new BusinessException(AuthErrorCode.REFRESH_TOKEN_INVALID);
    }
  }

  private VerifiedRefreshToken decode(String refreshToken) {
    try {
      return tokenDecoder.decode(refreshToken);
    } catch (JwtException exception) {
      throw new BusinessException(AuthErrorCode.REFRESH_TOKEN_INVALID, exception);
    }
  }
}
