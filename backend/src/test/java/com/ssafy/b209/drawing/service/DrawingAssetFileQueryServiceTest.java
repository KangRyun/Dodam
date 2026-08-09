package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.response.DrawingAssetFileResource;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.ByteArrayInputStream;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DrawingAssetFileQueryServiceTest {

  private static final Long DRAWING_ASSET_ID = 20L;
  private static final Long DRAWING_SESSION_ID = 10L;
  private static final Long GUARDIAN_USER_ID = 41L;
  private static final String STORAGE_KEY = "drafts/10/20.png";

  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private ImageStorage imageStorage;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;
  @Mock private DrawingAsset drawingAsset;
  @Mock private DrawingSession drawingSession;

  private DrawingAssetFileQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingAssetFileQueryService(
            drawingAssetRepository, imageStorage, currentUserResolver, accessValidator);
  }

  @Test
  void opensAnAccessibleDrawingAssetFromStorage() {
    StoredImageContent content =
        new StoredImageContent(new ByteArrayInputStream(new byte[] {1, 2, 3}), "image/png", 3);
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(drawingAssetRepository.findById(DRAWING_ASSET_ID)).willReturn(Optional.of(drawingAsset));
    given(drawingAsset.getDrawingSession()).willReturn(drawingSession);
    given(drawingSession.getId()).willReturn(DRAWING_SESSION_ID);
    given(drawingAsset.getStorageKey()).willReturn(STORAGE_KEY);
    given(imageStorage.read(STORAGE_KEY)).willReturn(content);

    DrawingAssetFileResource result = service.getFile(DRAWING_ASSET_ID);

    assertThat(result.content()).isSameAs(content);
    verify(accessValidator).requireDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID);
  }

  @Test
  void rejectsMissingAssetBeforeReadingStorage() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(drawingAssetRepository.findById(DRAWING_ASSET_ID)).willReturn(Optional.empty());

    assertBusinessError(
        () -> service.getFile(DRAWING_ASSET_ID), DrawingErrorCode.DRAWING_ASSET_NOT_FOUND);

    verifyNoInteractions(accessValidator, imageStorage);
  }

  @Test
  void hidesAnUnownedAssetsExistenceAndDoesNotReadStorage() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(drawingAssetRepository.findById(DRAWING_ASSET_ID)).willReturn(Optional.of(drawingAsset));
    given(drawingAsset.getDrawingSession()).willReturn(drawingSession);
    given(drawingSession.getId()).willReturn(DRAWING_SESSION_ID);
    willThrow(new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
        .given(accessValidator)
        .requireDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID);

    assertBusinessError(
        () -> service.getFile(DRAWING_ASSET_ID), DrawingErrorCode.DRAWING_SESSION_NOT_FOUND);

    verifyNoInteractions(imageStorage);
  }

  @Test
  void rejectsAnUnauthenticatedRequestBeforeLookingUpMetadata() {
    willThrow(new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED))
        .given(currentUserResolver)
        .requireUserId();

    assertThatThrownBy(() -> service.getFile(DRAWING_ASSET_ID))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.AUTHENTICATION_REQUIRED));

    verifyNoInteractions(drawingAssetRepository, accessValidator, imageStorage);
  }

  private void assertBusinessError(Runnable invocation, DrawingErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
