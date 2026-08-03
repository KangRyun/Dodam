package com.ssafy.b209.community.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.community.domain.CommunityAttachmentFile;
import com.ssafy.b209.community.exception.CommunityAttachmentErrorCode;
import com.ssafy.b209.community.repository.CommunityAttachmentFileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImage;
import java.io.ByteArrayInputStream;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

@ExtendWith(MockitoExtension.class)
class CommunityAttachmentUploadServiceTest {

  @Mock private CommunityAttachmentFileRepository repository;
  @Mock private ImageStorage imageStorage;
  private CommunityAttachmentUploadService service;

  @BeforeEach
  void setUp() {
    service =
        new CommunityAttachmentUploadService(
            repository,
            imageStorage,
            new CurrentAuthenticatedUserResolver(),
            Clock.fixed(Instant.parse("2026-08-03T00:00:00Z"), ZoneOffset.UTC));
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(41L), null, List.of()));
  }

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void storesValidatedImageMetadataForTwentyFourHours() {
    given(imageStorage.store(any()))
        .willReturn(
            new StoredImage(
                "community/file.png", "file.png", "image/png", 1024, "a".repeat(64), 640, 480));
    given(repository.saveAndFlush(any(CommunityAttachmentFile.class)))
        .willAnswer(invocation -> invocation.getArgument(0));

    var response = service.upload(command(1024));

    assertThat(response.fileId()).isNotBlank();
    assertThat(response.widthPx()).isEqualTo(640);
    assertThat(response.expiresAt()).isEqualTo(Instant.parse("2026-08-04T00:00:00Z"));
    verify(repository).saveAndFlush(any(CommunityAttachmentFile.class));
  }

  @Test
  void rejectsFileOverFiveMebibytesBeforeStorage() {
    assertThatThrownBy(
            () -> service.upload(command(CommunityAttachmentUploadService.MAX_FILE_SIZE_BYTES + 1)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommunityAttachmentErrorCode.FILE_TOO_LARGE));
  }

  private StoreImageCommand command(long size) {
    return new StoreImageCommand(
        new ByteArrayInputStream(new byte[] {1}), size, "image/png", "drawing.png");
  }
}
