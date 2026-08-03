package com.ssafy.b209.expert.service;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertCredential;
import com.ssafy.b209.expert.domain.ExpertCredentialFile;
import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.dto.response.ExpertCredentialResponse;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertCredentialRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.credential.CredentialFileStorage;
import java.time.ZoneOffset;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** 로그인 전문가가 보유한 자격 증빙을 조회하고 검토 전 자격을 삭제한다. */
@Service
public class ExpertCredentialManagementService {
  private static final Logger log =
      LoggerFactory.getLogger(ExpertCredentialManagementService.class);

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ExpertCredentialRepository credentialRepository;
  private final CredentialFileStorage fileStorage;

  /**
   * 자격 소유권 조회와 파일 수명주기에 필요한 의존성을 주입한다.
   *
   * @param currentUserResolver 로그인 사용자 식별자 확인 도구
   * @param credentialRepository 전문가 자격 저장소
   * @param fileStorage 자격 증빙 파일 Storage
   */
  public ExpertCredentialManagementService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ExpertCredentialRepository credentialRepository,
      CredentialFileStorage fileStorage) {
    this.currentUserResolver = currentUserResolver;
    this.credentialRepository = credentialRepository;
    this.fileStorage = fileStorage;
  }

  /**
   * 로그인 전문가의 자격을 최신 등록 순으로 조회한다.
   *
   * @return 내부 Storage Key를 제외한 자격 목록
   */
  @Transactional(readOnly = true)
  public List<ExpertCredentialResponse> listMine() {
    Long userId = currentUserResolver.requireUserId();
    return credentialRepository.findAllOwnedByUserId(userId).stream()
        .map(this::toResponse)
        .toList();
  }

  /**
   * 관리자 검토 전인 {@link ExpertVerificationStatus#PENDING} 자격을 삭제한다.
   *
   * <p>DB 삭제가 Commit된 뒤 Storage 파일을 삭제한다. 검토 이력이 있는 자격은 감사 근거 보존을 위해 삭제하지 않는다.
   *
   * @param credentialId 삭제할 자격 식별자
   * @throws BusinessException 자격이 없거나 본인 소유가 아니거나 삭제 가능 상태가 아닌 경우
   */
  @Transactional
  public void deleteMine(Long credentialId) {
    Long userId = currentUserResolver.requireUserId();
    ExpertCredential credential =
        credentialRepository
            .findOwnedById(credentialId, userId)
            .orElseThrow(() -> new BusinessException(ExpertErrorCode.CREDENTIAL_NOT_FOUND));
    if (credential.getVerificationStatus() != ExpertVerificationStatus.PENDING) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_DELETE_NOT_ALLOWED);
    }
    List<String> storageKeys =
        credential.getFiles().stream().map(ExpertCredentialFile::getStorageKey).toList();
    credentialRepository.delete(credential);
    deleteFilesAfterCommit(storageKeys);
  }

  private ExpertCredentialResponse toResponse(ExpertCredential credential) {
    ExpertCredentialFile file =
        credential.getFiles().stream()
            .findFirst()
            .orElseThrow(() -> new BusinessException(ExpertErrorCode.CREDENTIAL_NOT_FOUND));
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
        credential.getCreatedAt().toInstant(ZoneOffset.UTC));
  }

  private void deleteFilesAfterCommit(List<String> storageKeys) {
    Runnable deleteAction =
        () ->
            storageKeys.forEach(
                storageKey -> {
                  try {
                    fileStorage.delete(storageKey);
                  } catch (RuntimeException exception) {
                    log.error(
                        "자격 정보 삭제 후 증빙 파일 정리에 실패했습니다. credential file cleanup required.",
                        exception);
                  }
                });
    if (!TransactionSynchronizationManager.isSynchronizationActive()) {
      deleteAction.run();
      return;
    }
    TransactionSynchronizationManager.registerSynchronization(
        new TransactionSynchronization() {
          @Override
          public void afterCommit() {
            deleteAction.run();
          }
        });
  }
}
