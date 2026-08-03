package com.ssafy.b209.expert.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertProfile;
import com.ssafy.b209.expert.dto.request.UpdateExpertProfileRequest;
import com.ssafy.b209.expert.dto.response.ExpertProfileResponse;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertFollowSummary;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 인증된 전문가가 소유한 공개 프로필의 부분 수정을 처리한다. */
@Service
public class ExpertProfileUpdateService {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final UserRepository userRepository;
  private final ExpertProfileRepository expertProfileRepository;
  private final Clock clock;

  /**
   * 운영 시각을 사용하는 전문가 프로필 수정 서비스를 생성한다.
   *
   * @param currentUserResolver 인증 사용자 식별자 확인 도구
   * @param userRepository 역할과 계정 상태 저장소
   * @param expertProfileRepository 전문가 프로필 저장소
   */
  @Autowired
  public ExpertProfileUpdateService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      UserRepository userRepository,
      ExpertProfileRepository expertProfileRepository) {
    this(currentUserResolver, userRepository, expertProfileRepository, Clock.systemUTC());
  }

  ExpertProfileUpdateService(
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
   * 현재 전문가가 소유한 프로필에서 요청에 포함된 필드만 변경한다.
   *
   * @param request 부분 수정 요청
   * @return 변경 후 전문가 프로필
   * @throws BusinessException 활성 전문가 계정이 아니거나 프로필이 없거나 연령 범위가 올바르지 않은 경우
   */
  @Transactional
  public ExpertProfileResponse update(UpdateExpertProfileRequest request) {
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
    ExpertProfile profile =
        expertProfileRepository
            .findDetailByUserId(userId)
            .orElseThrow(() -> new BusinessException(ExpertErrorCode.EXPERT_PROFILE_NOT_FOUND));
    validateEffectiveAgeRange(profile, request);
    profile.update(request, LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
    ExpertFollowSummary followSummary =
        expertProfileRepository
            .findFollowSummaries(java.util.List.of(profile.getId()), userId)
            .stream()
            .findFirst()
            .orElse(null);
    return toResponse(profile, followSummary);
  }

  private void validateEffectiveAgeRange(
      ExpertProfile profile, UpdateExpertProfileRequest request) {
    Integer min =
        request.targetAgeMin() == null ? profile.getTargetAgeMin() : request.targetAgeMin();
    Integer max =
        request.targetAgeMax() == null ? profile.getTargetAgeMax() : request.targetAgeMax();
    if ((min == null) != (max == null) || (min != null && min > max)) {
      throw new BusinessException(ExpertErrorCode.EXPERT_PROFILE_INVALID);
    }
  }

  private ExpertProfileResponse toResponse(
      ExpertProfile profile, ExpertFollowSummary followSummary) {
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
        followSummary == null ? 0L : followSummary.getFollowerCount(),
        followSummary != null && followSummary.getFollowedByMe() == 1);
  }
}
