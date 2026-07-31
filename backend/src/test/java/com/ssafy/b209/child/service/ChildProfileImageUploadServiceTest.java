package com.ssafy.b209.child.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.ChildProfileImageFile;
import com.ssafy.b209.child.dto.response.ChildProfileImageUploadResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildProfileImageFileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImage;
import java.io.ByteArrayInputStream;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ChildProfileImageUploadServiceTest {

  private static final Instant NOW = Instant.parse("2026-07-31T00:00:00Z");

  @Mock private ChildProfileImageFileRepository repository;
  @Mock private ImageStorage imageStorage;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;

  private ChildProfileImageUploadService service;

  @BeforeEach
  void setUp() {
    service =
        new ChildProfileImageUploadService(
            repository, imageStorage, currentUserResolver, Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void storesAValidatedTemporaryProfileImage() {
    StoreImageCommand command = command(1024);
    StoredImage stored =
        new StoredImage(
            "2026/07/31/profile.png", "profile.png", "image/png", 1024, "a".repeat(64), 320, 320);
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(imageStorage.store(command)).willReturn(stored);
    given(repository.saveAndFlush(org.mockito.ArgumentMatchers.any(ChildProfileImageFile.class)))
        .willAnswer(invocation -> invocation.getArgument(0));

    ChildProfileImageUploadResponse response = service.upload(command);

    assertThat(response.profileImageFileId()).isNotBlank();
    assertThat(response.contentType()).isEqualTo("image/png");
    assertThat(response.fileSizeBytes()).isEqualTo(1024);
    assertThat(response.widthPx()).isEqualTo(320);
    assertThat(response.heightPx()).isEqualTo(320);
    assertThat(response.expiresAt()).isEqualTo(Instant.parse("2026-08-01T00:00:00Z"));
  }

  @Test
  void rejectsAnImageLargerThanFiveMebibytesBeforeStorage() {
    StoreImageCommand command = command(5L * 1024 * 1024 + 1);

    assertThatThrownBy(() -> service.upload(command))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_PROFILE_IMAGE_TOO_LARGE));
  }

  @Test
  void rejectsAMissingImage() {
    assertThatThrownBy(() -> service.upload(null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_PROFILE_IMAGE_FILE_REQUIRED));
  }

  @Test
  void deletesStoredBytesWhenMetadataPersistenceFails() {
    StoreImageCommand command = command(1024);
    StoredImage stored =
        new StoredImage(
            "2026/07/31/profile.png", "profile.png", "image/png", 1024, "a".repeat(64), 320, 320);
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(imageStorage.store(command)).willReturn(stored);
    given(repository.saveAndFlush(org.mockito.ArgumentMatchers.any(ChildProfileImageFile.class)))
        .willThrow(new IllegalStateException("database unavailable"));

    assertThatThrownBy(() -> service.upload(command))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_PROFILE_IMAGE_UPLOAD_FAILED));
    verify(imageStorage).delete(stored.storageKey());
  }

  private StoreImageCommand command(long size) {
    return new StoreImageCommand(
        new ByteArrayInputStream(new byte[] {1}), size, "image/png", "profile.png");
  }
}
