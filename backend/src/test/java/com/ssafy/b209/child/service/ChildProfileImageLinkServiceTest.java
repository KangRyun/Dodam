package com.ssafy.b209.child.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.child.domain.ChildProfileImageFile;
import com.ssafy.b209.child.domain.ChildProfileImageFileStatus;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildProfileImageDeletionRepository;
import com.ssafy.b209.child.repository.ChildProfileImageFileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ChildProfileImageLinkServiceTest {

  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-31T03:00:00Z"), ZoneOffset.UTC);

  @Mock private ChildProfileImageFileRepository repository;
  @Mock private ChildProfileImageDeletionRepository deletionRepository;

  private ChildProfileImageLinkService service;

  @BeforeEach
  void setUp() {
    service = new ChildProfileImageLinkService(repository, deletionRepository, CLOCK);
  }

  @Test
  void attachesOwnedUnexpiredTemporaryFile() {
    ChildProfileImageFile file = temporary(LocalDateTime.of(2026, 8, 1, 3, 0));
    given(repository.findByChildId(7L)).willReturn(Optional.empty());
    given(repository.findByFileIdAndUploadedByUserId("file-id", 10L)).willReturn(Optional.of(file));

    String url = service.attach(10L, 7L, "file-id");

    assertThat(url).isEqualTo("/api/v1/child-profile-images/file-id/file");
    assertThat(file.getStatus()).isEqualTo(ChildProfileImageFileStatus.ATTACHED);
    assertThat(file.getChildId()).isEqualTo(7L);
  }

  @Test
  void rejectsExpiredFileWithoutAttachingIt() {
    ChildProfileImageFile file = temporary(LocalDateTime.of(2026, 7, 31, 2, 59));
    given(repository.findByChildId(7L)).willReturn(Optional.empty());
    given(repository.findByFileIdAndUploadedByUserId("file-id", 10L)).willReturn(Optional.of(file));

    assertThatThrownBy(() -> service.attach(10L, 7L, "file-id"))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_PROFILE_IMAGE_LINK_CONFLICT));
  }

  @Test
  void hidesFilesOwnedByAnotherUserAsNotFound() {
    given(repository.findByChildId(7L)).willReturn(Optional.empty());
    given(repository.findByFileIdAndUploadedByUserId("file-id", 10L)).willReturn(Optional.empty());

    assertThatThrownBy(() -> service.attach(10L, 7L, "file-id"))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ChildErrorCode.CHILD_PROFILE_IMAGE_NOT_FOUND));
  }

  private ChildProfileImageFile temporary(LocalDateTime expiresAt) {
    return ChildProfileImageFile.temporary(
        "file-id",
        10L,
        "child-profile-images/file-id.png",
        "image/png",
        128,
        32,
        32,
        "a".repeat(64),
        expiresAt,
        LocalDateTime.of(2026, 7, 31, 2, 0));
  }
}
