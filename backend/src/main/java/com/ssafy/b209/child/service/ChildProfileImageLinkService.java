package com.ssafy.b209.child.service;

import com.ssafy.b209.child.domain.ChildProfileImageFile;
import com.ssafy.b209.child.domain.ChildProfileImageFileStatus;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildProfileImageDeletionRepository;
import com.ssafy.b209.child.repository.ChildProfileImageFileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 사전 업로드한 프로필 이미지를 아동과 연결하거나 기존 연결을 제거한다.
 *
 * <p>파일 소유권과 TEMP 만료 상태를 잠금 조회로 검증해 동일 파일이 두 아동에게 연결되는 경쟁 조건을 막는다.
 */
@Service
public class ChildProfileImageLinkService {

  private static final String FILE_URL_PREFIX = "/api/v1/child-profile-images/";
  private static final String FILE_URL_SUFFIX = "/file";

  private final ChildProfileImageFileRepository fileRepository;
  private final ChildProfileImageDeletionRepository deletionRepository;
  private final Clock clock;

  @Autowired
  public ChildProfileImageLinkService(
      ChildProfileImageFileRepository fileRepository,
      ChildProfileImageDeletionRepository deletionRepository) {
    this(fileRepository, deletionRepository, Clock.systemUTC());
  }

  ChildProfileImageLinkService(
      ChildProfileImageFileRepository fileRepository,
      ChildProfileImageDeletionRepository deletionRepository,
      Clock clock) {
    this.fileRepository = fileRepository;
    this.deletionRepository = deletionRepository;
    this.clock = clock;
  }

  /**
   * 업로드 파일을 아동 프로필에 연결한다.
   *
   * @param guardianUserId 파일을 업로드한 보호자 ID
   * @param childId 연결 대상 아동 ID
   * @param profileImageFileId 업로드 API가 발급한 파일 ID, 이미지가 없으면 {@code null}
   * @return 인증이 필요한 이미지 조회 URL, 이미지가 없으면 {@code null}
   */
  @Transactional
  public String attach(Long guardianUserId, Long childId, String profileImageFileId) {
    if (profileImageFileId == null) {
      return null;
    }
    return replace(guardianUserId, childId, profileImageFileId);
  }

  /**
   * 현재 이미지를 새 업로드 파일로 교체하거나 명시적 {@code null} 요청으로 삭제한다.
   *
   * @param guardianUserId 파일을 업로드한 보호자 ID
   * @param childId 변경 대상 아동 ID
   * @param profileImageFileId 새 파일 ID, 기존 이미지를 삭제하려면 {@code null}
   * @return 변경 후 이미지 조회 URL, 삭제한 경우 {@code null}
   */
  @Transactional
  public String replace(Long guardianUserId, Long childId, String profileImageFileId) {
    ChildProfileImageFile current = fileRepository.findByChildId(childId).orElse(null);
    if (current != null && current.getFileId().equals(profileImageFileId)) {
      return toFileUrl(current.getFileId());
    }
    if (profileImageFileId == null) {
      remove(current);
      return null;
    }
    LocalDateTime now = LocalDateTime.now(clock);
    ChildProfileImageFile file =
        fileRepository
            .findByFileIdAndUploadedByUserId(profileImageFileId, guardianUserId)
            .orElseThrow(() -> new BusinessException(ChildErrorCode.CHILD_PROFILE_IMAGE_NOT_FOUND));
    if (file.getStatus() != ChildProfileImageFileStatus.TEMP || !file.getExpiresAt().isAfter(now)) {
      throw new BusinessException(ChildErrorCode.CHILD_PROFILE_IMAGE_LINK_CONFLICT);
    }
    remove(current);
    try {
      file.attachTo(childId, now);
    } catch (IllegalStateException exception) {
      throw new BusinessException(ChildErrorCode.CHILD_PROFILE_IMAGE_LINK_CONFLICT);
    }
    return toFileUrl(file.getFileId());
  }

  /**
   * 현재 아동에 연결된 프로필 이미지의 삭제를 예약하고 Metadata 연결을 제거한다.
   *
   * @param childId 이미지 연결을 제거할 아동 ID
   */
  @Transactional
  public void removeCurrent(Long childId) {
    remove(fileRepository.findByChildId(childId).orElse(null));
  }

  private void remove(ChildProfileImageFile current) {
    if (current != null) {
      deletionRepository.schedule(current.getStorageKey(), current.getId());
      fileRepository.delete(current);
      fileRepository.flush();
    }
  }

  public static String toFileUrl(String fileId) {
    return FILE_URL_PREFIX + fileId + FILE_URL_SUFFIX;
  }
}
