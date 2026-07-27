package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AuthAccount;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.AuthAccountRepository;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 검증된 Kakao·Google·Naver 신원을 서비스 사용자와 인증 계정에 원자적으로 연결한다.
 *
 * <p>Provider 통신과 Token 발급은 담당하지 않는다. 호출자는 반드시 Provider 응답 검증을 마친 {@link VerifiedOAuthIdentity}만
 * 전달해야 한다.
 */
@Service
public class OAuthAccountProvisioningService {

  private final UserRepository userRepository;
  private final AuthAccountRepository authAccountRepository;
  private final Clock clock;

  /**
   * OAuth 계정 Provisioning Service를 구성한다.
   *
   * @param userRepository 사용자 저장소
   * @param authAccountRepository OAuth 인증 계정 저장소
   * @param clock 저장 시각을 제공하는 Clock
   */
  public OAuthAccountProvisioningService(
      UserRepository userRepository, AuthAccountRepository authAccountRepository, Clock clock) {
    this.userRepository = userRepository;
    this.authAccountRepository = authAccountRepository;
    this.clock = clock;
  }

  /**
   * 검증된 OAuth 신원에 해당하는 기존 사용자를 반환하거나 Onboarding 대기 사용자를 새로 생성한다.
   *
   * <p>동일한 {@code provider}와 {@code providerSubject}로 반복 호출하면 기존 계정을 반환한다. 동시 생성 경쟁으로 UNIQUE 제약이
   * 충돌하면 트랜잭션을 Rollback하고 안전한 충돌 오류로 변환한다.
   *
   * @param identity Provider 통신 계층에서 검증을 마친 OAuth 신원
   * @return 연결된 사용자와 Onboarding 필요 여부
   * @throws BusinessException 동일 OAuth 신원이 동시에 연결되어 계정을 확정할 수 없는 경우
   */
  @Transactional
  public ProvisionedOAuthAccount provision(VerifiedOAuthIdentity identity) {
    return authAccountRepository
        .findByProviderAndProviderSubject(identity.provider(), identity.providerSubject())
        .map(
            account ->
                new ProvisionedOAuthAccount(
                    account.getUser().getId(),
                    account.getProvider(),
                    account.getProviderEmail(),
                    false,
                    !account.getUser().isOnboardingCompleted()))
        .orElseGet(() -> createAccount(identity));
  }

  private ProvisionedOAuthAccount createAccount(VerifiedOAuthIdentity identity) {
    LocalDateTime now = LocalDateTime.now(clock);
    User user = userRepository.save(User.pending(now));
    LocalDateTime emailVerifiedAt = identity.providerEmail() == null ? null : now;
    AuthAccount authAccount =
        AuthAccount.social(
            user,
            identity.provider(),
            identity.providerSubject(),
            identity.providerEmail(),
            emailVerifiedAt,
            now);
    try {
      authAccountRepository.saveAndFlush(authAccount);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(AuthErrorCode.ACCOUNT_LINK_CONFLICT, exception);
    }
    return new ProvisionedOAuthAccount(
        user.getId(), identity.provider(), identity.providerEmail(), true, true);
  }
}
