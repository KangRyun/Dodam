package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.domain.CommunityAttachmentFile;
import com.ssafy.b209.community.domain.CommunityAttachmentStatus;
import com.ssafy.b209.community.dto.CommunityAttachmentFileResource;
import com.ssafy.b209.community.exception.CommunityAttachmentErrorCode;
import com.ssafy.b209.community.repository.CommunityAttachmentFileRepository;
import com.ssafy.b209.community.repository.CommunityPostDetailRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 인증 사용자에게 소유한 임시 이미지 또는 열람 가능한 게시글 첨부 이미지를 스트리밍한다. */
@Service
@Transactional(readOnly = true)
public class CommunityAttachmentFileQueryService {

  private final CommunityAttachmentFileRepository repository;
  private final CommunityPostDetailRepository postDetailRepository;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ImageStorage imageStorage;
  private final Clock clock;

  /**
   * 파일 Metadata와 공개 게시글 권한, 인증 사용자 및 Storage 조회 경계를 구성한다.
   *
   * @param repository 첨부 Metadata 저장소
   * @param postDetailRepository 게시글 공개 여부 확인 저장소
   * @param currentUserResolver 현재 인증 사용자 Resolver
   * @param imageStorage 이미지 조회 경계
   * @param clock 임시 파일 만료 판정에 사용하는 Clock
   */
  public CommunityAttachmentFileQueryService(
      CommunityAttachmentFileRepository repository,
      CommunityPostDetailRepository postDetailRepository,
      CurrentAuthenticatedUserResolver currentUserResolver,
      ImageStorage imageStorage,
      Clock clock) {
    this.repository = repository;
    this.postDetailRepository = postDetailRepository;
    this.currentUserResolver = currentUserResolver;
    this.imageStorage = imageStorage;
    this.clock = clock;
  }

  /**
   * 내부 Storage Key를 노출하지 않고 첨부 이미지 Stream을 반환한다.
   *
   * @param fileId 업로드 API가 발급한 파일 ID
   * @return 이미지 Stream과 불변 캐시 가능 여부
   * @throws BusinessException 파일이 없거나 요청자가 접근할 수 없는 경우
   */
  public CommunityAttachmentFileResource getFile(String fileId) {
    Long viewerId = currentUserResolver.requireUserId();
    CommunityAttachmentFile file =
        repository
            .findByFileId(fileId)
            .orElseThrow(() -> new BusinessException(CommunityAttachmentErrorCode.NOT_FOUND));
    boolean ownedTemporaryFile =
        file.getStatus() == CommunityAttachmentStatus.TEMP
            && viewerId.equals(file.getUploadedByUserId())
            && file.getExpiresAt().isAfter(LocalDateTime.now(clock));
    boolean publicAttachment =
        file.getStatus() == CommunityAttachmentStatus.ATTACHED
            && file.getPostId() != null
            && postDetailRepository.findPublicPost(file.getPostId(), viewerId).isPresent();
    if (!ownedTemporaryFile && !publicAttachment) {
      throw new BusinessException(CommunityAttachmentErrorCode.NOT_FOUND);
    }
    return new CommunityAttachmentFileResource(
        imageStorage.read(file.getStorageKey()),
        file.getStatus() == CommunityAttachmentStatus.ATTACHED);
  }
}
