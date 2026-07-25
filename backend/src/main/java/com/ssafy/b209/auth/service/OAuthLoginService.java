package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.token.IssuedTokenPair;
import com.ssafy.b209.auth.token.JwtTokenIssuer;
import com.ssafy.b209.auth.token.RefreshTokenHasher;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;

/** Provider Token 검증, 서비스 계정 연결, 로그인 시각 갱신과 JWT 발급을 조율한다. */
@Service
public class OAuthLoginService {

  private final OAuthProviderClient providerClient;
  private final OAuthAccountProvisioningService provisioningService;
  private final UserRepository userRepository;
  private final JwtTokenIssuer tokenIssuer;
  private final RefreshTokenHasher tokenHasher;
  private final RefreshTokenSessionStore sessionStore;
  private final Clock clock;

  /**
   * OAuth 로그인 Use Case를 구성한다.
   *
   * @param providerClient Provider Token 검증 Client
   * @param provisioningService 검증된 신원을 서비스 사용자와 연결하는 Service
   * @param userRepository 사용자 저장소
   * @param tokenIssuer 서비스 JWT 발급기
   * @param tokenHasher Redis 저장용 Refresh Token hash 계산기
   * @param sessionStore Refresh Token family 세션 저장소
   * @param clock 로그인 시각을 제공하는 Clock
   */
  public OAuthLoginService(
      OAuthProviderClient providerClient,
      OAuthAccountProvisioningService provisioningService,
      UserRepository userRepository,
      JwtTokenIssuer tokenIssuer,
      RefreshTokenHasher tokenHasher,
      RefreshTokenSessionStore sessionStore,
      Clock clock) {
    this.providerClient = providerClient;
    this.provisioningService = provisioningService;
    this.userRepository = userRepository;
    this.tokenIssuer = tokenIssuer;
    this.tokenHasher = tokenHasher;
    this.sessionStore = sessionStore;
    this.clock = clock;
  }

  /**
   * Provider Token으로 OAuth 신원을 확인하고 서비스 Token을 발급한다.
   *
   * @param provider Token을 발급한 OAuth Provider
   * @param request Provider Token과 기기 식별자
   * @return Access·Refresh Token과 사용자 상태
   * @throws BusinessException Provider 검증 실패, 계정 정지 또는 인증 설정 오류인 경우
   */
  public OAuthLoginResult login(AuthProvider provider, OAuthLoginRequest request) {
    OAuthProviderCredential credential = OAuthProviderCredential.from(provider, request);
    tokenIssuer.validateConfiguration();
    VerifiedOAuthIdentity identity = providerClient.verify(provider, credential);
    ProvisionedOAuthAccount provisioned = provisioningService.provision(identity);
    User user =
        userRepository
            .findById(provisioned.userId())
            .orElseThrow(() -> new BusinessException(AuthErrorCode.AUTH_ACCOUNT_INVALID));
    if (user.getAccountStatus() == AccountStatus.SUSPENDED
        || user.getAccountStatus() == AccountStatus.DELETED) {
      throw new BusinessException(AuthErrorCode.ACCOUNT_SUSPENDED);
    }
    user.recordSuccessfulLogin(LocalDateTime.now(clock));
    userRepository.save(user);
    IssuedTokenPair tokens = tokenIssuer.issue(user.getId());
    registerRefreshSession(user.getId(), request.deviceId(), tokens);
    String email = user.getEmail() != null ? user.getEmail() : identity.providerEmail();
    OAuthLoginUser loginUser =
        new OAuthLoginUser(
            user.getId(),
            user.getRole(),
            user.getNickname(),
            email,
            email == null,
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

  private void registerRefreshSession(Long userId, String deviceId, IssuedTokenPair tokens) {
    try {
      sessionStore.register(
          tokens.refreshTokenFamilyId(),
          userId,
          deviceId,
          tokenHasher.hash(tokens.refreshToken()),
          Duration.ofSeconds(tokens.refreshTokenExpiresInSeconds()));
    } catch (DataAccessException exception) {
      throw new BusinessException(AuthErrorCode.AUTH_SESSION_UNAVAILABLE, exception);
    }
  }
}
