package com.ssafy.b209.expert.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertProfile;
import com.ssafy.b209.expert.dto.request.CreateExpertProfileRequest;
import com.ssafy.b209.expert.dto.response.ExpertProfileResponse;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Locale;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증된 전문가 사용자의 최초 공개 프로필 등록을 조율한다.
 *
 * <p>활성 EXPERT 역할과 사용자당 단일 프로필 제약을 확인하고 전문 분야를 같은 Transaction에서 저장한다. 신규 프로필은 관리자 검증 전 {@code
 * PENDING}으로만 생성한다.
 */
@Service
public class ExpertProfileCreationService {

  private static final String USER_PROFILE_UNIQUE_CONSTRAINT = "uk_expert_profiles_user_id";

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final UserRepository userRepository;
  private final ExpertProfileRepository expertProfileRepository;
  private final Clock clock;

  /**
   * 운영 시각을 사용하는 전문가 프로필 생성 서비스를 만든다.
   *
   * @param currentUserResolver 인증 사용자 확인 도구
   * @param userRepository 역할과 계정 상태 조회 저장소
   * @param expertProfileRepository 전문가 프로필 저장소
   */
  @Autowired
  public ExpertProfileCreationService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      UserRepository userRepository,
      ExpertProfileRepository expertProfileRepository) {
    this(currentUserResolver, userRepository, expertProfileRepository, Clock.systemUTC());
  }

  ExpertProfileCreationService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      UserRepository userRepository,
      ExpertProfileRepository expertProfileRepository,
      Clock clock) {
    this.currentUserResolver = currentUserResolver;
    this.userRepository = userRepository;
    this.expertProfileRepository = expertProfileRepository;
    this.clock = clock;
  }

  /**
   * 인증 사용자의 전문가 프로필을 검토 대기 상태로 생성한다.
   *
   * @param request 공개 프로필 입력값
   * @return 생성된 전문가 프로필
   * @throws BusinessException 사용자가 활성 전문가가 아니거나 이미 프로필이 존재하는 경우
   */
  @Transactional
  public ExpertProfileResponse create(CreateExpertProfileRequest request) {
    Long userId = currentUserResolver.requireUserId();
    User user =
        userRepository
            .findById(userId)
            .orElseThrow(() -> new BusinessException(AuthErrorCode.ACCESS_DENIED));
    if (user.getRole() != UserRole.EXPERT
        || user.getAccountStatus() != AccountStatus.ACTIVE
        || !user.isOnboardingCompleted()) {
      throw new BusinessException(AuthErrorCode.ACCESS_DENIED);
    }
    if (expertProfileRepository.existsByUserId(userId)) {
      throw new BusinessException(ExpertErrorCode.EXPERT_PROFILE_ALREADY_EXISTS);
    }

    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    ExpertProfile profile = ExpertProfile.pending(userId, user.getProfileImageUrl(), request, now);
    try {
      ExpertProfile saved = expertProfileRepository.saveAndFlush(profile);
      return toResponse(saved);
    } catch (DataIntegrityViolationException exception) {
      if (isUserProfileUniqueConstraintViolation(exception)) {
        throw new BusinessException(ExpertErrorCode.EXPERT_PROFILE_ALREADY_EXISTS, exception);
      }
      throw exception;
    }
  }

  private boolean isUserProfileUniqueConstraintViolation(
      DataIntegrityViolationException exception) {
    String message = exception.getMostSpecificCause().getMessage();
    return message != null
        && message.toLowerCase(Locale.ROOT).contains(USER_PROFILE_UNIQUE_CONSTRAINT);
  }

  private ExpertProfileResponse toResponse(ExpertProfile profile) {
    return new ExpertProfileResponse(
        profile.getId(),
        profile.getDisplayName(),
        profile.getProfileImageUrl(),
        profile.getOrganization(),
        profile.getPositionTitle(),
        profile.getCareerYears(),
        profile.getSpecialtyCodes(),
        profile.getTargetAgeMin(),
        profile.getTargetAgeMax(),
        profile.getIntroduction(),
        profile.isConsultationAvailable(),
        profile.getVerificationStatus(),
        profile.getWorkplace(),
        0L,
        false);
  }
}
