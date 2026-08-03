package com.ssafy.b209.expert.service;

import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertCredential;
import com.ssafy.b209.expert.domain.ExpertProfile;
import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.dto.request.ReviewExpertVerificationRequest;
import com.ssafy.b209.expert.dto.response.ExpertVerificationResponse;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertCredentialRepository;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.expert.repository.ExpertVerificationAuditRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 관리자 권한을 확인하고 전문가 프로필과 자격의 승인·반려 상태를 원자적으로 확정한다. */
@Service
public class ExpertVerificationService {

  private static final String NOTIFICATION_TYPE = "EXPERT_VERIFICATION_RESULT";

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final UserRepository userRepository;
  private final ExpertProfileRepository profileRepository;
  private final ExpertCredentialRepository credentialRepository;
  private final ExpertVerificationAuditRepository auditRepository;
  private final NotificationRepository notificationRepository;
  private final Clock clock;

  /**
   * 전문가 검증 처리에 필요한 저장소와 인증 정보를 구성한다.
   *
   * @param currentUserResolver 현재 관리자 사용자 확인 도구
   * @param userRepository 역할 확인용 사용자 저장소
   * @param profileRepository 검토 대상 전문가 프로필 저장소
   * @param credentialRepository 전문가 자격 저장소
   * @param auditRepository 검토 사유와 감사 이력 저장소
   * @param notificationRepository 전문가 알림함 저장소
   * @param clock 서버 검토 시각 공급자
   */
  public ExpertVerificationService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      UserRepository userRepository,
      ExpertProfileRepository profileRepository,
      ExpertCredentialRepository credentialRepository,
      ExpertVerificationAuditRepository auditRepository,
      NotificationRepository notificationRepository,
      Clock clock) {
    this.currentUserResolver = currentUserResolver;
    this.userRepository = userRepository;
    this.profileRepository = profileRepository;
    this.credentialRepository = credentialRepository;
    this.auditRepository = auditRepository;
    this.notificationRepository = notificationRepository;
    this.clock = clock;
  }

  /**
   * 전문가 프로필을 승인 또는 반려하고 선택 자격, 감사 이력, 알림함을 함께 갱신한다.
   *
   * <p>승인 요청은 한 개 이상의 소유 자격을 명시해야 하며 선택된 자격만 승인한다. 반려 요청은 승인 자격 없이 공개 반려 사유를 제공해야 하고, 아직 승인되지 않은
   * 자격을 함께 반려한다.
   *
   * @param expertId 검토 대상 전문가 프로필 ID
   * @param request 최종 상태와 선택 자격·사유
   * @return 검토 후 프로필과 전체 자격 상태
   * @throws BusinessException 관리자가 아니거나 요청과 대상 상태가 유효하지 않은 경우
   */
  @Transactional
  public ExpertVerificationResponse review(Long expertId, ReviewExpertVerificationRequest request) {
    Long reviewerUserId = requireAdmin();
    validateRequest(request);
    ExpertProfile profile =
        profileRepository
            .findById(expertId)
            .orElseThrow(() -> new BusinessException(ExpertErrorCode.EXPERT_PROFILE_NOT_FOUND));
    List<ExpertCredential> credentials = credentialRepository.findAllForReview(expertId);
    Set<Long> requestedIds = new HashSet<>(request.verifiedCredentialIds());
    Set<Long> ownedIds =
        credentials.stream()
            .map(ExpertCredential::getId)
            .collect(java.util.stream.Collectors.toSet());
    if (!ownedIds.containsAll(requestedIds)) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_NOT_FOUND);
    }

    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    if (request.status() == ExpertVerificationStatus.VERIFIED) {
      credentials.stream()
          .filter(credential -> requestedIds.contains(credential.getId()))
          .forEach(
              credential ->
                  credential.completeVerification(ExpertVerificationStatus.VERIFIED, now));
    } else {
      credentials.stream()
          .filter(
              credential -> credential.getVerificationStatus() != ExpertVerificationStatus.VERIFIED)
          .forEach(
              credential ->
                  credential.completeVerification(ExpertVerificationStatus.REJECTED, now));
    }
    profile.completeVerification(request.status(), now);
    auditRepository.saveReview(
        reviewerUserId,
        expertId,
        request.status(),
        request.verifiedCredentialIds(),
        normalize(request.rejectionReason()),
        normalize(request.internalNote()),
        now);
    notificationRepository.save(
        Notification.create(
            profile.getUserId(),
            NOTIFICATION_TYPE,
            "전문가 자격 검토가 완료됐어요",
            notificationContent(request.status(), request.rejectionReason()),
            null,
            null,
            null,
            now));

    return new ExpertVerificationResponse(
        profile.getId(),
        profile.getVerificationStatus(),
        credentials.stream()
            .map(
                credential ->
                    new ExpertVerificationResponse.CredentialStatus(
                        credential.getId(), credential.getVerificationStatus()))
            .toList(),
        now.toInstant(ZoneOffset.UTC));
  }

  private Long requireAdmin() {
    Long userId = currentUserResolver.requireUserId();
    boolean admin =
        userRepository.findById(userId).map(user -> user.getRole() == UserRole.ADMIN).orElse(false);
    if (!admin) {
      throw new BusinessException(AuthErrorCode.ACCESS_DENIED);
    }
    return userId;
  }

  private void validateRequest(ReviewExpertVerificationRequest request) {
    if (request == null
        || (request.status() != ExpertVerificationStatus.VERIFIED
            && request.status() != ExpertVerificationStatus.REJECTED)
        || request.verifiedCredentialIds() == null
        || new HashSet<>(request.verifiedCredentialIds()).size()
            != request.verifiedCredentialIds().size()
        || (request.status() == ExpertVerificationStatus.VERIFIED
            && request.verifiedCredentialIds().isEmpty())
        || (request.status() == ExpertVerificationStatus.REJECTED
            && (!request.verifiedCredentialIds().isEmpty()
                || normalize(request.rejectionReason()) == null))) {
      throw new BusinessException(ExpertErrorCode.EXPERT_VERIFICATION_REQUEST_INVALID);
    }
  }

  private String notificationContent(ExpertVerificationStatus status, String rejectionReason) {
    if (status == ExpertVerificationStatus.VERIFIED) {
      return "제출한 전문가 자격이 승인되었습니다.";
    }
    return "제출한 전문가 자격이 반려되었습니다. 사유: " + normalize(rejectionReason);
  }

  private String normalize(String value) {
    return value == null || value.isBlank() ? null : value.trim();
  }
}
