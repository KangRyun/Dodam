package com.ssafy.b209.community.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.community.domain.CommunityAttachmentFile;
import com.ssafy.b209.community.domain.CommunityAttachmentStatus;
import com.ssafy.b209.community.domain.CommunityAttachmentType;
import com.ssafy.b209.community.dto.CommunityAttachmentInput;
import com.ssafy.b209.community.exception.CommunityAttachmentErrorCode;
import com.ssafy.b209.community.repository.CommunityAttachmentDeletionRepository;
import com.ssafy.b209.community.repository.CommunityAttachmentFileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CommunityAttachmentServiceTest {

  private static final Instant NOW = Instant.parse("2026-08-03T00:00:00Z");
  @Mock private CommunityAttachmentFileRepository repository;
  @Mock private CommunityAttachmentDeletionRepository deletionRepository;

  @Test
  void attachesOwnedTemporaryFilesInRequestOrder() {
    CommunityAttachmentFile second = temporary("second", NOW.plusSeconds(3600));
    CommunityAttachmentFile first = temporary("first", NOW.plusSeconds(3600));
    given(repository.findOwnedFilesForUpdate(Set.of("first", "second"), 41L))
        .willReturn(List.of(second, first));
    CommunityAttachmentService service = service();

    var response =
        service.attach(
            41L,
            100L,
            List.of(
                new CommunityAttachmentInput("first", CommunityAttachmentType.IMAGE),
                new CommunityAttachmentInput("second", CommunityAttachmentType.IMAGE)));

    assertThat(response).extracting(item -> item.fileId()).containsExactly("first", "second");
    assertThat(first.getStatus()).isEqualTo(CommunityAttachmentStatus.ATTACHED);
    assertThat(first.getDisplayOrder()).isZero();
    assertThat(second.getDisplayOrder()).isEqualTo(1);
  }

  @Test
  void rejectsExpiredTemporaryFile() {
    CommunityAttachmentFile expired = temporary("expired", NOW.minusSeconds(1));
    given(repository.findOwnedFilesForUpdate(Set.of("expired"), 41L)).willReturn(List.of(expired));

    assertThatThrownBy(
            () ->
                service()
                    .attach(
                        41L,
                        100L,
                        List.of(
                            new CommunityAttachmentInput(
                                "expired", CommunityAttachmentType.IMAGE))))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommunityAttachmentErrorCode.NOT_ATTACHABLE));
  }

  @Test
  void rejectsDuplicateFileReference() {
    var input = new CommunityAttachmentInput("same", CommunityAttachmentType.IMAGE);

    assertThatThrownBy(() -> service().attach(41L, 100L, List.of(input, input)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommunityAttachmentErrorCode.DUPLICATED));
  }

  private CommunityAttachmentService service() {
    return new CommunityAttachmentService(
        repository, deletionRepository, Clock.fixed(NOW, ZoneOffset.UTC));
  }

  private CommunityAttachmentFile temporary(String fileId, Instant expiresAt) {
    return CommunityAttachmentFile.temporary(
        fileId,
        41L,
        "community/" + fileId + ".png",
        "image/png",
        1024,
        640,
        480,
        "a".repeat(64),
        LocalDateTime.ofInstant(expiresAt, ZoneOffset.UTC),
        LocalDateTime.ofInstant(NOW.minusSeconds(60), ZoneOffset.UTC));
  }
}
