package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.request.UploadDrawingSnapshotRequest;
import com.ssafy.b209.drawing.dto.response.UploadDrawingSnapshotResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoreImageCommand;
import com.ssafy.b209.storage.image.StoredImage;
import java.io.ByteArrayInputStream;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class DrawingSnapshotServiceTest {

  private static final Instant NOW = Instant.parse("2026-07-22T01:00:00Z");
  private static final Long SESSION_ID = 10L;
  private static final Long GUARDIAN_USER_ID = 41L;
  private static final String STORAGE_KEY = "2026/07/image.png";

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private ImageStorage imageStorage;
  @Mock private DrawingSession drawingSession;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private DrawingSnapshotService service;
  private StoreImageCommand file;

  @BeforeEach
  void setUp() {
    service =
        new DrawingSnapshotService(
            drawingSessionRepository,
            drawingAssetRepository,
            imageStorage,
            currentUserResolver,
            accessValidator,
            Clock.fixed(NOW, ZoneOffset.UTC));
    file = new StoreImageCommand(new ByteArrayInputStream(new byte[] {1}), 1, "image/png", "a.png");
  }

  @Test
  void rejectsUnownedSessionBeforeStoringSnapshot() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
        .given(accessValidator)
        .requireDrawingSessionAccess(GUARDIAN_USER_ID, SESSION_ID);

    assertThatThrownBy(
            () -> service.upload(SESSION_ID, file, request(DrawingAssetType.INTERMEDIATE, 1)))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(drawingSessionRepository, drawingAssetRepository, imageStorage);
  }

  @Test
  void storesImageAndMetadataForUploadableSession() {
    UploadDrawingSnapshotRequest request = request(DrawingAssetType.INTERMEDIATE, 2);
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getId()).willReturn(SESSION_ID);
    given(drawingSession.isSnapshotUploadable()).willReturn(true);
    given(imageStorage.store(file))
        .willReturn(new StoredImage(STORAGE_KEY, "image.png", "image/png", 1, "a".repeat(64)));
    given(drawingAssetRepository.saveAndFlush(any(DrawingAsset.class)))
        .willAnswer(
            invocation -> {
              DrawingAsset asset = invocation.getArgument(0);
              ReflectionTestUtils.setField(asset, "id", 20L);
              return asset;
            });

    UploadDrawingSnapshotResponse response = service.upload(SESSION_ID, file, request);

    assertThat(response.drawingAssetId()).isEqualTo(20L);
    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.assetType()).isEqualTo(DrawingAssetType.INTERMEDIATE);
    assertThat(response.assetVersion()).isEqualTo(2);
    assertThat(response.checksumSha256()).isEqualTo("a".repeat(64));
    assertThat(response.uploadedAt()).isEqualTo(NOW);
    verify(imageStorage).store(file);
    verify(imageStorage, never()).delete(any());
  }

  @Test
  void rejectsMissingSessionBeforeStoringFile() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.empty());

    assertError(
        () -> service.upload(SESSION_ID, file, request(DrawingAssetType.INTERMEDIATE, 1)),
        DrawingErrorCode.DRAWING_SESSION_NOT_FOUND);
    verifyNoInteractions(imageStorage);
  }

  @Test
  void rejectsDuplicateVersionAndFinalSnapshotBeforeStoringFile() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.isSnapshotUploadable()).willReturn(true);
    given(
            drawingAssetRepository.existsByDrawingSessionIdAndAssetTypeAndAssetVersion(
                SESSION_ID, DrawingAssetType.INTERMEDIATE, 1))
        .willReturn(true);

    assertError(
        () -> service.upload(SESSION_ID, file, request(DrawingAssetType.INTERMEDIATE, 1)),
        DrawingErrorCode.DRAWING_SNAPSHOT_SEQUENCE_CONFLICT);

    given(
            drawingAssetRepository.existsByDrawingSessionIdAndAssetTypeAndAssetVersion(
                SESSION_ID, DrawingAssetType.FINAL, 2))
        .willReturn(false);
    given(
            drawingAssetRepository.existsByDrawingSessionIdAndAssetType(
                SESSION_ID, DrawingAssetType.FINAL))
        .willReturn(true);

    assertError(
        () -> service.upload(SESSION_ID, file, request(DrawingAssetType.FINAL, 2)),
        DrawingErrorCode.DRAWING_FINAL_SNAPSHOT_EXISTS);
    verifyNoInteractions(imageStorage);
  }

  @Test
  void deletesStoredFileWhenMetadataSaveFails() {
    UploadDrawingSnapshotRequest request = request(DrawingAssetType.INTERMEDIATE, 1);
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.isSnapshotUploadable()).willReturn(true);
    given(imageStorage.store(file))
        .willReturn(new StoredImage(STORAGE_KEY, "image.png", "image/png", 1, "a".repeat(64)));
    given(drawingAssetRepository.saveAndFlush(any(DrawingAsset.class)))
        .willThrow(new DataIntegrityViolationException("duplicate"));

    assertError(
        () -> service.upload(SESSION_ID, file, request),
        DrawingErrorCode.DRAWING_SNAPSHOT_CREATION_CONFLICT);
    verify(imageStorage).delete(STORAGE_KEY);
  }

  private UploadDrawingSnapshotRequest request(DrawingAssetType type, int version) {
    return new UploadDrawingSnapshotRequest(
        type, version, OffsetDateTime.parse("2026-07-22T09:30:00+09:00"));
  }

  private void assertError(Runnable invocation, DrawingErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
