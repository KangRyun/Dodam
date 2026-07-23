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
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.request.SaveDrawingDraftRequest;
import com.ssafy.b209.drawing.dto.response.DrawingDraftResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingDraftDeletionRepository;
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
class DrawingDraftServiceTest {

  private static final Long SESSION_ID = 10L;
  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Instant NOW = Instant.parse("2026-07-22T05:30:01Z");
  private static final String STORAGE_KEY = "drafts/10/new.png";

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private DrawingDraftDeletionRepository drawingDraftDeletionRepository;
  @Mock private ImageStorage imageStorage;
  @Mock private DrawingSession drawingSession;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private DrawingDraftService service;
  private StoreImageCommand preview;

  @BeforeEach
  void setUp() {
    service =
        new DrawingDraftService(
            drawingSessionRepository,
            drawingAssetRepository,
            drawingDraftDeletionRepository,
            imageStorage,
            currentUserResolver,
            accessValidator,
            Clock.fixed(NOW, ZoneOffset.UTC));
    preview =
        new StoreImageCommand(
            new ByteArrayInputStream(new byte[] {1}), 1, "image/png", "draft.png");
  }

  @Test
  void rejectsUnownedSessionBeforeReadingDraftMetadata() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
        .given(accessValidator)
        .requireDrawingSessionAccess(GUARDIAN_USER_ID, SESSION_ID);

    assertThatThrownBy(() -> service.getLatest(SESSION_ID)).isInstanceOf(BusinessException.class);

    verifyNoInteractions(drawingSessionRepository, drawingAssetRepository, imageStorage);
  }

  @Test
  void storesFirstDraftWithServerAssignedVersion() {
    allowSession();
    given(drawingAssetRepository.findLatestDraft(SESSION_ID)).willReturn(Optional.empty());
    given(imageStorage.store(preview)).willReturn(storedImage());
    given(drawingAssetRepository.saveAndFlush(any(DrawingAsset.class)))
        .willAnswer(invocation -> saved(invocation.getArgument(0), 20L));

    DrawingDraftResponse response = service.save(SESSION_ID, preview, request(11));

    assertThat(response.drawingAssetId()).isEqualTo(20L);
    assertThat(response.assetVersion()).isEqualTo(1);
    assertThat(response.lastEventSequence()).isEqualTo(11);
    assertThat(response.finalSnapshot()).isFalse();
    assertThat(response.savedAt()).isEqualTo(NOW);
    verify(imageStorage).store(preview);
    verify(imageStorage, never()).delete(any());
  }

  @Test
  void incrementsVersionWhenNewerEventSequenceArrives() {
    allowSession();
    given(drawingAssetRepository.findLatestDraft(SESSION_ID))
        .willReturn(Optional.of(draft(3, 30, 19L)));
    given(imageStorage.store(preview)).willReturn(storedImage());
    given(drawingAssetRepository.saveAndFlush(any(DrawingAsset.class)))
        .willAnswer(invocation -> saved(invocation.getArgument(0), 20L));

    DrawingDraftResponse response = service.save(SESSION_ID, preview, request(31));

    assertThat(response.assetVersion()).isEqualTo(4);
    assertThat(response.lastEventSequence()).isEqualTo(31);
  }

  @Test
  void rejectsSameAndOlderEventSequenceBeforeStoringFile() {
    allowSession();
    given(drawingAssetRepository.findLatestDraft(SESSION_ID))
        .willReturn(Optional.of(draft(3, 30, 19L)));

    assertError(
        () -> service.save(SESSION_ID, preview, request(30)),
        DrawingErrorCode.DRAWING_DRAFT_VERSION_CONFLICT);
    assertError(
        () -> service.save(SESSION_ID, preview, request(29)),
        DrawingErrorCode.STALE_DRAWING_DRAFT_VERSION);
    verifyNoInteractions(imageStorage);
  }

  @Test
  void rejectsSessionOutsideInProgressDrawingStage() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.isSnapshotUploadable()).willReturn(false);

    assertError(
        () -> service.save(SESSION_ID, preview, request(1)),
        DrawingErrorCode.DRAWING_DRAFT_NOT_ALLOWED);
    verifyNoInteractions(imageStorage);
  }

  @Test
  void deletesStoredImageWhenMetadataSaveConflicts() {
    allowSession();
    given(drawingAssetRepository.findLatestDraft(SESSION_ID)).willReturn(Optional.empty());
    given(imageStorage.store(preview)).willReturn(storedImage());
    given(drawingAssetRepository.saveAndFlush(any(DrawingAsset.class)))
        .willThrow(new DataIntegrityViolationException("duplicate"));

    assertError(
        () -> service.save(SESSION_ID, preview, request(1)),
        DrawingErrorCode.DRAWING_DRAFT_SAVE_CONFLICT);
    verify(imageStorage).delete(STORAGE_KEY);
  }

  @Test
  void returnsLatestDraftAndReportsNotFound() {
    given(drawingSessionRepository.findNotDeletedById(SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    DrawingAsset latest = draft(4, 31, 20L);
    given(drawingAssetRepository.findLatestDraft(SESSION_ID)).willReturn(Optional.of(latest));

    assertThat(service.getLatest(SESSION_ID).drawingAssetId()).isEqualTo(20L);

    given(drawingAssetRepository.findLatestDraft(SESSION_ID)).willReturn(Optional.empty());
    assertError(() -> service.getLatest(SESSION_ID), DrawingErrorCode.DRAWING_DRAFT_NOT_FOUND);
  }

  @Test
  void deletesAllDraftMetadataAndSchedulesStoredFiles() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingDraftDeletionRepository.scheduleAndDeleteAll(SESSION_ID)).willReturn(2);

    service.delete(SESSION_ID);

    verify(accessValidator).requireDrawingSessionAccess(GUARDIAN_USER_ID, SESSION_ID);
    verify(drawingDraftDeletionRepository).scheduleAndDeleteAll(SESSION_ID);
  }

  @Test
  void reportsNotFoundWhenSessionHasNoDraft() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingDraftDeletionRepository.scheduleAndDeleteAll(SESSION_ID)).willReturn(0);

    assertError(() -> service.delete(SESSION_ID), DrawingErrorCode.DRAWING_DRAFT_NOT_FOUND);
  }

  private void allowSession() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.isSnapshotUploadable()).willReturn(true);
  }

  private SaveDrawingDraftRequest request(long lastEventSequence) {
    return new SaveDrawingDraftRequest(
        lastEventSequence, OffsetDateTime.parse("2026-07-22T14:30:00+09:00"));
  }

  private DrawingAsset draft(int version, long lastEventSequence, long id) {
    DrawingAsset asset =
        DrawingAsset.draft(
            drawingSession,
            version,
            "drafts/10/old.png",
            "image/png",
            10,
            "a".repeat(64),
            lastEventSequence,
            NOW.atOffset(ZoneOffset.UTC).toLocalDateTime(),
            NOW.atOffset(ZoneOffset.UTC).toLocalDateTime());
    return saved(asset, id);
  }

  private DrawingAsset saved(DrawingAsset asset, long id) {
    ReflectionTestUtils.setField(asset, "id", id);
    return asset;
  }

  private StoredImage storedImage() {
    return new StoredImage(STORAGE_KEY, "new.png", "image/png", 1, "b".repeat(64));
  }

  private void assertError(Runnable invocation, DrawingErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
