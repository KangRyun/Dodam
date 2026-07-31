package com.ssafy.b209.child.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.ChildProfileImageFile;
import com.ssafy.b209.child.domain.ChildProfileImageFileStatus;
import com.ssafy.b209.child.dto.response.ChildProfileImageFileResource;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildProfileImageFileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 인증 보호자에게 연결된 아동 프로필 이미지를 Storage에서 조회한다. */
@Service
@Transactional(readOnly = true)
public class ChildProfileImageFileQueryService {

  private final ChildProfileImageFileRepository repository;
  private final ImageStorage imageStorage;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;

  public ChildProfileImageFileQueryService(
      ChildProfileImageFileRepository repository,
      ImageStorage imageStorage,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this.repository = repository;
    this.imageStorage = imageStorage;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
  }

  /**
   * 프로필 이미지 Metadata와 아동 접근 권한을 확인한 뒤 이미지 Stream을 연다.
   *
   * @param fileId 업로드 API가 발급한 프로필 이미지 ID
   * @return 응답 전송 후 닫아야 하는 이미지 Resource
   */
  public ChildProfileImageFileResource getFile(String fileId) {
    ChildProfileImageFile file =
        repository
            .findByFileId(fileId)
            .filter(candidate -> candidate.getStatus() == ChildProfileImageFileStatus.ATTACHED)
            .filter(candidate -> candidate.getChildId() != null)
            .orElseThrow(() -> new BusinessException(ChildErrorCode.CHILD_PROFILE_IMAGE_NOT_FOUND));
    accessValidator.requireChildAccess(currentUserResolver.requireUserId(), file.getChildId());
    return new ChildProfileImageFileResource(imageStorage.read(file.getStorageKey()));
  }
}
