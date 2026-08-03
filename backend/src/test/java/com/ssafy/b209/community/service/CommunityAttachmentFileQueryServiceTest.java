package com.ssafy.b209.community.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.community.domain.CommunityAttachmentFile;
import com.ssafy.b209.community.exception.CommunityAttachmentErrorCode;
import com.ssafy.b209.community.repository.CommunityAttachmentFileRepository;
import com.ssafy.b209.community.repository.CommunityPostDetailRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.ByteArrayInputStream;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

@ExtendWith(MockitoExtension.class)
class CommunityAttachmentFileQueryServiceTest {

  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-08-03T00:00:00Z"), ZoneOffset.UTC);

  @Mock private CommunityAttachmentFileRepository repository;
  @Mock private CommunityPostDetailRepository postDetailRepository;
  @Mock private ImageStorage imageStorage;
  private CommunityAttachmentFileQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new CommunityAttachmentFileQueryService(
            repository,
            postDetailRepository,
            new CurrentAuthenticatedUserResolver(),
            imageStorage,
            CLOCK);
    authenticate(41L);
  }

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void letsUploaderPreviewTemporaryFileWithoutExposingStorageKey() {
    CommunityAttachmentFile file = temporary("file-id", 41L);
    given(repository.findByFileId("file-id")).willReturn(Optional.of(file));
    given(imageStorage.read("community/file-id.png"))
        .willReturn(
            new StoredImageContent(new ByteArrayInputStream(new byte[] {1}), "image/png", 1));

    var resource = service.getFile("file-id");

    assertThat(resource.immutable()).isFalse();
    assertThat(resource.content().contentType()).isEqualTo("image/png");
  }

  @Test
  void hidesAnotherUsersTemporaryFileAsNotFound() {
    given(repository.findByFileId("file-id")).willReturn(Optional.of(temporary("file-id", 42L)));

    assertThatThrownBy(() -> service.getFile("file-id"))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommunityAttachmentErrorCode.NOT_FOUND));
  }

  @Test
  void hidesExpiredTemporaryFileFromUploader() {
    given(repository.findByFileId("file-id"))
        .willReturn(
            Optional.of(temporary("file-id", 41L, LocalDateTime.parse("2026-08-02T23:59:59"))));

    assertThatThrownBy(() -> service.getFile("file-id"))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommunityAttachmentErrorCode.NOT_FOUND));
  }

  @Test
  void hidesAttachedFileFromUploaderWhenPostIsNotPubliclyAccessible() {
    CommunityAttachmentFile file = temporary("file-id", 41L);
    file.attachTo(17L, 0, LocalDateTime.parse("2026-08-03T00:01:00"));
    given(repository.findByFileId("file-id")).willReturn(Optional.of(file));
    given(postDetailRepository.findPublicPost(17L, 41L)).willReturn(Optional.empty());

    assertThatThrownBy(() -> service.getFile("file-id"))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommunityAttachmentErrorCode.NOT_FOUND));
  }

  private CommunityAttachmentFile temporary(String fileId, Long userId) {
    return temporary(fileId, userId, LocalDateTime.parse("2099-01-01T00:00:00"));
  }

  private CommunityAttachmentFile temporary(String fileId, Long userId, LocalDateTime expiresAt) {
    return CommunityAttachmentFile.temporary(
        fileId,
        userId,
        "community/" + fileId + ".png",
        "image/png",
        1,
        1,
        1,
        "a".repeat(64),
        expiresAt,
        LocalDateTime.parse("2026-08-03T00:00:00"));
  }

  private void authenticate(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
