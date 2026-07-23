package com.ssafy.b209.user.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.consent.dto.request.CreateConsentRequest;
import com.ssafy.b209.consent.service.ConsentRegistrationService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.OnboardingRequest;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.exception.UserErrorCode;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 신규 사용자의 최초 정보와 필수 약관 동의를 한 트랜잭션에서 확정하고 Onboarding을 완료 처리한다.
 *
 * <p>이미 완료한 사용자가 다시 호출하면 상태를 변경하지 않고 현재 정보를 반환하는 멱등 동작을 보장한다. 약관 동의 검증과 저장은 기존 {@link
 * ConsentRegistrationService}에 위임한다.
 */
@Service
public class UserOnboardingService {

  private final UserRepository userRepository;
  private final ConsentRegistrationService consentRegistrationService;
  private final Clock clock;

  /**
   * Onboarding Use Case를 구성한다.
   *
   * @param userRepository 사용자 저장소
   * @param consentRegistrationService 사용자 범위 필수 동의 검증·저장 Service
   */
  @Autowired
  public UserOnboardingService(
      UserRepository userRepository, ConsentRegistrationService consentRegistrationService) {
    this(userRepository, consentRegistrationService, Clock.systemUTC());
  }

  UserOnboardingService(
      UserRepository userRepository,
      ConsentRegistrationService consentRegistrationService,
      Clock clock) {
    this.userRepository = userRepository;
    this.consentRegistrationService = consentRegistrationService;
    this.clock = clock;
  }

  /**
   * 인증 사용자의 최초 정보를 확정하고 필수 약관 동의를 저장한다.
   *
   * @param userId 인증된 사용자 식별자
   * @param request 역할·닉네임·이메일과 약관 동의 결과
   * @param ipAddress 동의 증빙으로 기록할 원격 IP, 확인할 수 없으면 {@code null}
   * @param userAgent 동의 증빙으로 기록할 User-Agent, 확인할 수 없으면 {@code null}
   * @return 완료된 사용자 상태
   * @throws BusinessException 역할이 허용되지 않거나 사용자를 찾을 수 없거나 필수 동의가 누락된 경우
   */
  @Transactional
  public UserResponse completeOnboarding(
      Long userId, OnboardingRequest request, String ipAddress, String userAgent) {
    if (request.role() == UserRole.ADMIN) {
      throw new BusinessException(UserErrorCode.ROLE_NOT_ALLOWED);
    }
    User user =
        userRepository
            .findById(userId)
            .orElseThrow(() -> new BusinessException(UserErrorCode.USER_NOT_FOUND));

    if (user.isOnboardingCompleted()) {
      return toResponse(user);
    }

    consentRegistrationService.register(
        userId, new CreateConsentRequest(null, request.consents()), ipAddress, userAgent);
    user.completeOnboarding(
        request.role(), request.nickname(), request.email(), LocalDateTime.now(clock));
    userRepository.save(user);
    return toResponse(user);
  }

  private UserResponse toResponse(User user) {
    return new UserResponse(
        user.getId(),
        user.getRole(),
        user.getNickname(),
        user.getEmail(),
        user.getAccountStatus(),
        user.isOnboardingCompleted());
  }
}
