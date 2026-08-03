package com.ssafy.b209.expert.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertCredential;
import com.ssafy.b209.expert.domain.ExpertCredentialFile;
import com.ssafy.b209.expert.domain.ExpertProfile;
import com.ssafy.b209.expert.dto.request.UploadExpertCredentialRequest;
import com.ssafy.b209.expert.dto.response.ExpertCredentialResponse;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertCredentialRepository;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.credential.CredentialFileStorage;
import com.ssafy.b209.storage.credential.StoreCredentialFileCommand;
import com.ssafy.b209.storage.credential.StoredCredentialFile;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** 인증된 전문가의 자격 Metadata와 보호된 증빙 파일을 원자적으로 연결한다. */
@Service
public class ExpertCredentialUploadService {
  private static final Logger log = LoggerFactory.getLogger(ExpertCredentialUploadService.class);

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final UserRepository userRepository;
  private final ExpertProfileRepository profileRepository;
  private final ExpertCredentialRepository credentialRepository;
  private final CredentialFileStorage fileStorage;
  private final Clock clock;

  /**
   * 자격 업로드에 필요한 권한·DB·Storage 경계를 주입한다.
   *
   * @param currentUserResolver 인증 사용자 식별자 확인 도구
   * @param userRepository 역할과 계정 상태 저장소
   * @param profileRepository 전문가 프로필 저장소
   * @param credentialRepository 자격과 파일 Metadata 저장소
   * @param fileStorage 자격 증빙 파일 Storage
   * @param clock 등록 시각 기준 시계
   */
  public ExpertCredentialUploadService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      UserRepository userRepository,
      ExpertProfileRepository profileRepository,
      ExpertCredentialRepository credentialRepository,
      CredentialFileStorage fileStorage,
      Clock clock) {
    this.currentUserResolver = currentUserResolver;
    this.userRepository = userRepository;
    this.profileRepository = profileRepository;
    this.credentialRepository = credentialRepository;
    this.fileStorage = fileStorage;
    this.clock = clock;
  }

  /**
   * 파일을 검증·저장하고 자격 Metadata를 검토 대기 상태로 등록한다.
   *
   * <p>DB Transaction이 Rollback되면 이미 저장한 객체를 보상 삭제한다. 검증이 완료된 프로필에 새 자격이 추가되면 프로필을 재검토 상태로 전환한다.
   *
   * @param command 파일 Byte와 선언 Metadata
   * @param request 자격 Metadata
   * @return 내부 Storage Key를 제외한 등록 결과
   * @throws BusinessException 활성 전문가가 아니거나 프로필·파일 계약을 충족하지 못한 경우
   */
  @Transactional
  public ExpertCredentialResponse upload(
      StoreCredentialFileCommand command, UploadExpertCredentialRequest request) {
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
        profileRepository
            .findDetailByUserId(userId)
            .orElseThrow(() -> new BusinessException(ExpertErrorCode.EXPERT_PROFILE_NOT_FOUND));

    StoredCredentialFile stored = fileStorage.store(command);
    registerRollbackCleanup(stored.storageKey());
    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    ExpertCredential credential = ExpertCredential.pending(profile, request, now);
    ExpertCredentialFile file =
        ExpertCredentialFile.first(credential, stored, command.originalFilename(), now);
    credential.addFile(file);
    profile.requireCredentialReview(now);
    credentialRepository.saveAndFlush(credential);
    return new ExpertCredentialResponse(
        credential.getId(),
        credential.getCredentialType(),
        credential.getCredentialName(),
        credential.getIssuer(),
        credential.getIssuedAt(),
        credential.getCredentialNumberMasked(),
        credential.getVerificationStatus(),
        file.getFileName(),
        file.getMimeType(),
        file.getFileSizeBytes(),
        now.toInstant(ZoneOffset.UTC));
  }

  private void registerRollbackCleanup(String storageKey) {
    if (!TransactionSynchronizationManager.isSynchronizationActive()) return;
    TransactionSynchronizationManager.registerSynchronization(
        new TransactionSynchronization() {
          @Override
          public void afterCompletion(int status) {
            if (status != STATUS_ROLLED_BACK) return;
            try {
              fileStorage.delete(storageKey);
            } catch (RuntimeException exception) {
              log.warn("자격 Metadata Rollback 후 증빙 파일 보상 삭제에 실패했습니다.");
            }
          }
        });
  }
}
