package com.ssafy.b209.child.service;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.ChildProfileImageFile;
import com.ssafy.b209.child.dto.response.ChildProfileImageUploadResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildProfileImageFileRepository;
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

/**
 * 아동 프로필 이미지의 전용 크기 정책을 검사하고 임시 파일 식별자를 발급한다.
 *
 * <p>이미지 Signature·차원·Checksum 검증과 실제 저장은 공통 {@link ImageStorage}에 위임한다. DB 반영 실패 시 저장된 객체를 보상 삭제해
 * 연결되지 않은 파일이 남지 않도록 한다.
 */
@Service
public class ChildProfileImageUploadService {

  static final long MAX_PROFILE_IMAGE_SIZE_BYTES = 5L * 1024 * 1024;
  static final Duration TEMP_FILE_TTL = Duration.ofHours(24);

  private static final Logger log = LoggerFactory.getLogger(ChildProfileImageUploadService.class);

  private final ChildProfileImageFileRepository repository;
  private final ImageStorage imageStorage;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final Clock clock;

  /**
   * 프로필 이미지 업로드에 필요한 영속성·Storage·인증 경계를 구성한다.
   *
   * @param repository 임시 파일 Metadata 저장소
   * @param imageStorage 이미지 검증 및 저장 경계
   * @param currentUserResolver 현재 인증 사용자 Resolver
   * @param clock 만료 시각 계산 기준
   */
  public ChildProfileImageUploadService(
      ChildProfileImageFileRepository repository,
      ImageStorage imageStorage,
      CurrentAuthenticatedUserResolver currentUserResolver,
      Clock clock) {
    this.repository = repository;
    this.imageStorage = imageStorage;
    this.currentUserResolver = currentUserResolver;
    this.clock = clock;
  }

  /**
   * PNG 또는 JPEG 프로필 이미지를 임시 저장하고 연결에 사용할 식별자를 발급한다.
   *
   * @param image 업로드 이미지 Stream과 호출자 Metadata
   * @return 공개 파일 식별자와 검증된 이미지 Metadata
   * @throws BusinessException 파일이 없거나 5 MiB를 초과하거나 저장에 실패한 경우
   */
  @Transactional
  public ChildProfileImageUploadResponse upload(StoreImageCommand image) {
    validate(image);
    Long userId = currentUserResolver.requireUserId();
    StoredImage stored = imageStorage.store(image);
    LocalDateTime createdAt = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    LocalDateTime expiresAt = createdAt.plus(TEMP_FILE_TTL);
    ChildProfileImageFile file =
        ChildProfileImageFile.temporary(
            UUID.randomUUID().toString(),
            userId,
            stored.storageKey(),
            stored.contentType(),
            stored.size(),
            stored.widthPx(),
            stored.heightPx(),
            stored.checksumSha256(),
            expiresAt,
            createdAt);
    try {
      ChildProfileImageFile saved = repository.saveAndFlush(file);
      return new ChildProfileImageUploadResponse(
          saved.getFileId(),
          saved.getContentType(),
          saved.getFileSizeBytes(),
          saved.getWidthPx(),
          saved.getHeightPx(),
          saved.getExpiresAt().toInstant(ZoneOffset.UTC));
    } catch (RuntimeException exception) {
      compensate(stored.storageKey());
      throw new BusinessException(ChildErrorCode.CHILD_PROFILE_IMAGE_UPLOAD_FAILED, exception);
    }
  }

  private void validate(StoreImageCommand image) {
    if (image == null || image.inputStream() == null || image.size() <= 0) {
      throw new BusinessException(ChildErrorCode.CHILD_PROFILE_IMAGE_FILE_REQUIRED);
    }
    if (image.size() > MAX_PROFILE_IMAGE_SIZE_BYTES) {
      throw new BusinessException(ChildErrorCode.CHILD_PROFILE_IMAGE_TOO_LARGE);
    }
  }

  private void compensate(String storageKey) {
    try {
      imageStorage.delete(storageKey);
    } catch (RuntimeException cleanupException) {
      log.warn("아동 프로필 이미지 Metadata 저장 실패 후 파일 보상 삭제에 실패했습니다.");
    }
  }
}
