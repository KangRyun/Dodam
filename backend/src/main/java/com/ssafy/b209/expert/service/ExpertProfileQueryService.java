package com.ssafy.b209.expert.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertProfile;
import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.dto.response.ExpertProfilePageResponse;
import com.ssafy.b209.expert.dto.response.ExpertProfileResponse;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertFollowSummary;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import jakarta.persistence.criteria.JoinType;
import java.util.Collection;
import java.util.Locale;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 인증된 보호자·전문가에게 공개 전문가 목록과 상세 프로필을 제공한다.
 *
 * <p>검색 조건과 검증 상태 노출 정책을 적용하고 팔로우 집계를 응답에 결합한다. 검증 전 상세 정보는 프로필 소유자만 확인할 수 있다.
 */
@Service
public class ExpertProfileQueryService {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final UserRepository userRepository;
  private final ExpertProfileRepository expertProfileRepository;

  /**
   * 전문가 프로필 조회 서비스를 생성한다.
   *
   * @param currentUserResolver 현재 사용자 확인 도구
   * @param userRepository 계정 역할·상태 저장소
   * @param expertProfileRepository 프로필·팔로우 조회 저장소
   */
  public ExpertProfileQueryService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      UserRepository userRepository,
      ExpertProfileRepository expertProfileRepository) {
    this.currentUserResolver = currentUserResolver;
    this.userRepository = userRepository;
    this.expertProfileRepository = expertProfileRepository;
  }

  /**
   * 조건에 맞는 공개 전문가 프로필을 페이지로 조회한다.
   *
   * @return 프로필 목록과 페이지 정보
   */
  @Transactional(readOnly = true)
  public ExpertProfilePageResponse getProfiles(
      String specialty,
      Boolean consultationAvailable,
      boolean verifiedOnly,
      String keyword,
      int page,
      int size) {
    User currentUser = requireEligibleUser();
    Specification<ExpertProfile> specification =
        buildSpecification(specialty, consultationAvailable, verifiedOnly, keyword);
    Page<ExpertProfile> found =
        expertProfileRepository.findAll(
            specification,
            PageRequest.of(
                page,
                size,
                Sort.by(Sort.Order.desc("verificationStatus"), Sort.Order.asc("displayName"))));
    Map<Long, ExpertFollowSummary> follows =
        followSummaries(found.getContent(), currentUser.getId());
    return new ExpertProfilePageResponse(
        found.getContent().stream()
            .map(profile -> toResponse(profile, follows.get(profile.getId())))
            .toList(),
        found.getNumber(),
        found.getSize(),
        found.getTotalElements(),
        found.getTotalPages(),
        found.hasNext());
  }

  /**
   * 공개 전문가 상세 프로필을 조회한다.
   *
   * @param expertId 전문가 프로필 식별자
   * @return 전문 분야와 팔로우 정보를 포함한 프로필
   * @throws BusinessException 프로필이 없거나 검증 전 타인 프로필인 경우
   */
  @Transactional(readOnly = true)
  public ExpertProfileResponse getProfile(Long expertId) {
    User currentUser = requireEligibleUser();
    ExpertProfile profile =
        expertProfileRepository
            .findDetailById(expertId)
            .orElseThrow(() -> new BusinessException(ExpertErrorCode.EXPERT_PROFILE_NOT_FOUND));
    if (profile.getVerificationStatus() != ExpertVerificationStatus.VERIFIED
        && !profile.getUserId().equals(currentUser.getId())) {
      throw new BusinessException(ExpertErrorCode.EXPERT_NOT_VERIFIED);
    }
    ExpertFollowSummary follow =
        followSummaries(java.util.List.of(profile), currentUser.getId()).get(profile.getId());
    return toResponse(profile, follow);
  }

  private User requireEligibleUser() {
    Long userId = currentUserResolver.requireUserId();
    User user =
        userRepository
            .findById(userId)
            .orElseThrow(() -> new BusinessException(AuthErrorCode.ACCESS_DENIED));
    if (user.getAccountStatus() != AccountStatus.ACTIVE
        || !user.isOnboardingCompleted()
        || (user.getRole() != UserRole.GUARDIAN && user.getRole() != UserRole.EXPERT)) {
      throw new BusinessException(AuthErrorCode.ACCESS_DENIED);
    }
    return user;
  }

  private Specification<ExpertProfile> buildSpecification(
      String specialty, Boolean consultationAvailable, boolean verifiedOnly, String keyword) {
    return (root, query, criteriaBuilder) -> {
      var predicates = new java.util.ArrayList<jakarta.persistence.criteria.Predicate>();
      if (verifiedOnly) {
        predicates.add(
            criteriaBuilder.equal(
                root.get("verificationStatus"), ExpertVerificationStatus.VERIFIED));
      }
      if (consultationAvailable != null) {
        predicates.add(
            criteriaBuilder.equal(root.get("consultationAvailable"), consultationAvailable));
      }
      if (specialty != null && !specialty.isBlank()) {
        query.distinct(true);
        predicates.add(
            criteriaBuilder.equal(
                root.join("specialties", JoinType.INNER).get("specialtyCode"),
                specialty.trim().toUpperCase(Locale.ROOT)));
      }
      if (keyword != null && !keyword.isBlank()) {
        String pattern = "%" + keyword.trim().toLowerCase(Locale.ROOT) + "%";
        predicates.add(
            criteriaBuilder.or(
                criteriaBuilder.like(criteriaBuilder.lower(root.get("displayName")), pattern),
                criteriaBuilder.like(criteriaBuilder.lower(root.get("organization")), pattern)));
      }
      return criteriaBuilder.and(predicates.toArray(jakarta.persistence.criteria.Predicate[]::new));
    };
  }

  private Map<Long, ExpertFollowSummary> followSummaries(
      Collection<ExpertProfile> profiles, Long currentUserId) {
    if (profiles.isEmpty()) {
      return Map.of();
    }
    return expertProfileRepository
        .findFollowSummaries(profiles.stream().map(ExpertProfile::getId).toList(), currentUserId)
        .stream()
        .collect(Collectors.toMap(ExpertFollowSummary::getExpertId, Function.identity()));
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
