package com.ssafy.b209.community.service;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.community.domain.CommunityAttachmentFile;
import com.ssafy.b209.community.dto.CommunityAttachmentUploadResponse;
import com.ssafy.b209.community.exception.CommunityAttachmentErrorCode;
import com.ssafy.b209.community.repository.CommunityAttachmentFileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImage;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 커뮤니티 이미지를 검증·임시 저장하고 게시글 요청에 사용할 파일 ID를 발급한다. */
@Service
public class CommunityAttachmentUploadService {

  static final long MAX_FILE_SIZE_BYTES = 5L * 1024 * 1024;
  static final Duration TEMP_FILE_TTL = Duration.ofHours(24);

  private static final Logger log = LoggerFactory.getLogger(CommunityAttachmentUploadService.class);

  private final CommunityAttachmentFileRepository repository;
  private final ImageStorage imageStorage;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final Clock clock;

  /**
   * 업로드에 필요한 Metadata·Storage·인증 경계와 시간 기준을 구성한다.
   *
   * @param repository 첨부 Metadata 저장소
   * @param imageStorage 이미지 검증·저장 경계
   * @param currentUserResolver 현재 인증 사용자 Resolver
   * @param clock 임시 파일 만료 시각 기준
   */
  public CommunityAttachmentUploadService(
      CommunityAttachmentFileRepository repository,
      ImageStorage imageStorage,
      CurrentAuthenticatedUserResolver currentUserResolver,
      Clock clock) {
    this.repository = repository;
    this.imageStorage = imageStorage;
    this.currentUserResolver = currentUserResolver;
    this.clock = clock;
  }

  /**
   * PNG 또는 JPEG 이미지를 최대 5 MiB까지 임시 저장한다.
   *
   * @param image 업로드 이미지 Stream과 호출자 Metadata
   * @return 게시글 작성·수정 요청에 사용할 파일 ID와 검증 Metadata
   * @throws BusinessException 파일 누락, 크기 초과 또는 저장 실패인 경우
   */
  @Transactional
  public CommunityAttachmentUploadResponse upload(StoreImageCommand image) {
    validate(image);
    Long userId = currentUserResolver.requireUserId();
    StoredImage stored = imageStorage.store(image);
    LocalDateTime createdAt = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    CommunityAttachmentFile file =
        CommunityAttachmentFile.temporary(
            UUID.randomUUID().toString(),
            userId,
            stored.storageKey(),
            stored.contentType(),
            stored.size(),
            stored.widthPx(),
            stored.heightPx(),
            stored.checksumSha256(),
            createdAt.plus(TEMP_FILE_TTL),
            createdAt);
    try {
      CommunityAttachmentFile saved = repository.saveAndFlush(file);
      return new CommunityAttachmentUploadResponse(
          saved.getFileId(),
          saved.getContentType(),
          saved.getFileSizeBytes(),
          saved.getWidthPx(),
          saved.getHeightPx(),
          saved.getExpiresAt().toInstant(ZoneOffset.UTC));
    } catch (RuntimeException exception) {
      compensate(stored.storageKey());
      throw new BusinessException(CommunityAttachmentErrorCode.UPLOAD_FAILED, exception);
    }
  }

  private void validate(StoreImageCommand image) {
    if (image == null || image.inputStream() == null || image.size() <= 0) {
      throw new BusinessException(CommunityAttachmentErrorCode.FILE_REQUIRED);
    }
    if (image.size() > MAX_FILE_SIZE_BYTES) {
      throw new BusinessException(CommunityAttachmentErrorCode.FILE_TOO_LARGE);
    }
  }

  private void compensate(String storageKey) {
    try {
      imageStorage.delete(storageKey);
    } catch (RuntimeException cleanupException) {
      log.warn("커뮤니티 첨부 Metadata 저장 실패 후 파일 보상 삭제에 실패했습니다.");
    }
  }
}
