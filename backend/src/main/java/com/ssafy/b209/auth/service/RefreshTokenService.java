package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.dto.request.TokenReissueRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.token.IssuedTokenPair;
import com.ssafy.b209.auth.token.JwtRefreshTokenDecoder;
import com.ssafy.b209.auth.token.JwtTokenIssuer;
import com.ssafy.b209.auth.token.RefreshTokenHasher;
import com.ssafy.b209.auth.token.VerifiedRefreshToken;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Duration;
import org.springframework.dao.DataAccessException;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.stereotype.Service;

/** Refresh JWT와 Redis 세션을 함께 검증하고 Token pair를 rotation하는 Use Case를 수행한다. */
@Service
public class RefreshTokenService {

  private final JwtRefreshTokenDecoder tokenDecoder;
  private final JwtTokenIssuer tokenIssuer;
  private final RefreshTokenHasher tokenHasher;
  private final RefreshTokenSessionStore sessionStore;
  private final UserRepository userRepository;

  /**
   * Refresh Token 재발급 Service를 구성한다.
   *
   * @param tokenDecoder Refresh JWT 검증기
   * @param tokenIssuer 새 서비스 JWT 발급기
   * @param tokenHasher Redis 비교용 Token hash 계산기
   * @param sessionStore Refresh Token rotation 저장소
   * @param userRepository 현재 사용자 상태 조회 저장소
   */
  public RefreshTokenService(
      JwtRefreshTokenDecoder tokenDecoder,
      JwtTokenIssuer tokenIssuer,
      RefreshTokenHasher tokenHasher,
      RefreshTokenSessionStore sessionStore,
      UserRepository userRepository) {
    this.tokenDecoder = tokenDecoder;
    this.tokenIssuer = tokenIssuer;
    this.tokenHasher = tokenHasher;
    this.sessionStore = sessionStore;
    this.userRepository = userRepository;
  }

  /**
   * Refresh Token을 검증하고 동일 family의 새 Token pair로 원자적으로 교체한다.
   *
   * @param request 현재 Refresh Token과 최초 로그인 기기 식별자
   * @return 새 Access·Refresh Token과 현재 사용자 상태
   * @throws BusinessException JWT, 세션, 기기 또는 사용자 상태가 유효하지 않은 경우
   */
  public OAuthLoginResult reissue(TokenReissueRequest request) {
    VerifiedRefreshToken verified = decode(request.refreshToken());
    User user =
        userRepository
            .findById(verified.userId())
            .orElseThrow(() -> new BusinessException(AuthErrorCode.REFRESH_TOKEN_INVALID));
    if (user.getAccountStatus() == AccountStatus.SUSPENDED
        || user.getAccountStatus() == AccountStatus.WITHDRAWN) {
      throw new BusinessException(AuthErrorCode.ACCOUNT_SUSPENDED);
    }

    IssuedTokenPair tokens = tokenIssuer.issue(user.getId(), verified.familyId());
    RefreshTokenRotationResult rotation = rotate(request, verified, tokens);
    if (rotation == RefreshTokenRotationResult.INVALID) {
      throw new BusinessException(AuthErrorCode.REFRESH_TOKEN_INVALID);
    }
    if (rotation == RefreshTokenRotationResult.DEVICE_MISMATCH) {
      throw new BusinessException(AuthErrorCode.REFRESH_TOKEN_DEVICE_MISMATCH);
    }
    if (rotation == RefreshTokenRotationResult.REUSED) {
      throw new BusinessException(AuthErrorCode.REFRESH_TOKEN_REUSED);
    }

    OAuthLoginUser loginUser =
        new OAuthLoginUser(
            user.getId(),
            user.getRole(),
            user.getNickname(),
            user.getAccountStatus(),
            user.isOnboardingCompleted());
    return new OAuthLoginResult(
        "Bearer",
        tokens.accessToken(),
        tokens.accessTokenExpiresInSeconds(),
        tokens.refreshToken(),
        tokens.refreshTokenExpiresInSeconds(),
        loginUser);
  }

  private VerifiedRefreshToken decode(String refreshToken) {
    try {
      return tokenDecoder.decode(refreshToken);
    } catch (JwtException exception) {
      throw new BusinessException(AuthErrorCode.REFRESH_TOKEN_INVALID, exception);
    }
  }

  private RefreshTokenRotationResult rotate(
      TokenReissueRequest request, VerifiedRefreshToken verified, IssuedTokenPair tokens) {
    try {
      return sessionStore.rotate(
          verified.familyId(),
          verified.userId(),
          request.deviceId(),
          tokenHasher.hash(request.refreshToken()),
          tokenHasher.hash(tokens.refreshToken()),
          Duration.ofSeconds(tokens.refreshTokenExpiresInSeconds()));
    } catch (DataAccessException exception) {
      throw new BusinessException(AuthErrorCode.AUTH_SESSION_UNAVAILABLE, exception);
    }
  }
}
