package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.request.UploadDrawingImageRequest;
import com.ssafy.b209.drawing.dto.response.UploadDrawingImageResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
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
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class DrawingImageUploadServiceTest {

  private static final long SESSION_ID = 10L;
  private static final long GUARDIAN_ID = 20L;
  private static final String KEY = "htp-upload-key-0001";
  private static final Instant NOW = Instant.parse("2026-07-29T01:00:00Z");

  @Mock private DrawingSessionRepository sessionRepository;
  @Mock private DrawingAssetRepository assetRepository;
  @Mock private HtpAssessmentRepository htpAssessmentRepository;
  @Mock private ImageStorage imageStorage;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;
  @Mock private DrawingAssetFileUrlFactory fileUrlFactory;
  @Mock private DrawingSession session;
  @Mock private HtpAssessmentStep step;

  private DrawingImageUploadService service;
  private StoreImageCommand image;

  @BeforeEach
  void setUp() {
    service =
        new DrawingImageUploadService(
            sessionRepository,
            assetRepository,
            htpAssessmentRepository,
            imageStorage,
            currentUserResolver,
            accessValidator,
            fileUrlFactory,
            Clock.fixed(NOW, ZoneOffset.UTC));
    image =
        new StoreImageCommand(
            new ByteArrayInputStream(new byte[] {1}), 1, "image/png", "house.png");
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
  }

  @Test
  void storesUploadedAssetForUploadHtpSession() {
    prepareUploadableSession();
    given(assetRepository.findByUploadIdempotencyKey(KEY)).willReturn(Optional.empty());
    given(
            assetRepository.existsByDrawingSessionIdAndAssetType(
                SESSION_ID, com.ssafy.b209.drawing.domain.DrawingAssetType.UPLOADED))
        .willReturn(false);
    given(imageStorage.store(image)).willReturn(storedImage());
    given(fileUrlFactory.create(30L)).willReturn("/api/v1/drawing-assets/30/file");
    given(assetRepository.saveAndFlush(any(DrawingAsset.class)))
        .willAnswer(
            invocation -> {
              DrawingAsset asset = invocation.getArgument(0);
              ReflectionTestUtils.setField(asset, "id", 30L);
              return asset;
            });

    UploadDrawingImageResponse response = service.upload(SESSION_ID, KEY, image, validRequest());

    assertThat(response.drawingAssetId()).isEqualTo(30L);
    assertThat(response.drawingSubject()).isEqualTo(HtpDrawingSubject.HOUSE);
    assertThat(response.previewUrl()).isEqualTo("/api/v1/drawing-assets/30/file");
    assertThat(response.widthPx()).isEqualTo(1200);
    assertThat(response.heightPx()).isEqualTo(800);
    assertThat(response.qualityWarnings()).isEmpty();
  }

  @Test
  void rejectsCanvasSessionBeforeStoringImage() {
    prepareSession(DrawingInputMethod.CANVAS);
    given(assetRepository.findByUploadIdempotencyKey(KEY)).willReturn(Optional.empty());

    assertError(
        () -> service.upload(SESSION_ID, KEY, image, validRequest()),
        DrawingErrorCode.DRAWING_UPLOAD_NOT_SUPPORTED);

    verify(imageStorage, never()).store(any());
  }

  @Test
  void rejectsGeneralDrawingSessionBeforeStoringImage() {
    prepareSession(DrawingInputMethod.UPLOAD);
    given(session.getId()).willReturn(SESSION_ID);
    given(htpAssessmentRepository.findStepByDrawingSessionId(SESSION_ID))
        .willReturn(Optional.empty());
    given(assetRepository.findByUploadIdempotencyKey(KEY)).willReturn(Optional.empty());

    assertError(
        () -> service.upload(SESSION_ID, KEY, image, validRequest()),
        DrawingErrorCode.DRAWING_UPLOAD_NOT_SUPPORTED);

    verify(imageStorage, never()).store(any());
  }

  private void prepareUploadableSession() {
    prepareSession(DrawingInputMethod.UPLOAD);
    given(session.getId()).willReturn(SESSION_ID);
    given(session.isSnapshotUploadable()).willReturn(true);
    given(htpAssessmentRepository.findStepByDrawingSessionId(SESSION_ID))
        .willReturn(Optional.of(step));
    given(step.getDrawingSubject()).willReturn(HtpDrawingSubject.HOUSE);
  }

  private void prepareSession(DrawingInputMethod inputMethod) {
    given(sessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(session));
    given(session.getInputMethod()).willReturn(inputMethod);
  }

  private UploadDrawingImageRequest validRequest() {
    return new UploadDrawingImageRequest(
        OffsetDateTime.parse("2026-07-29T09:30:00+09:00"), 0, true);
  }

  private StoredImage storedImage() {
    return new StoredImage(
        "images/house.png", "house.png", "image/png", 100, "a".repeat(64), 1200, 800);
  }

  private void assertError(Runnable invocation, DrawingErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
