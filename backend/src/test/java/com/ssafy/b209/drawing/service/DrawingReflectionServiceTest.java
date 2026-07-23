package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.SaveDrawingReflectionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingReflectionResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DrawingReflectionServiceTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long DRAWING_SESSION_ID = 10L;

  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;
  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private DrawingSessionEmotionRepository emotionRepository;
  @Mock private DrawingSession drawingSession;

  @InjectMocks private DrawingReflectionService service;

  @BeforeEach
  void setUp() {
    lenient().when(currentUserResolver.requireUserId()).thenReturn(GUARDIAN_USER_ID);
  }

  @Test
  void replacesEmotionsInRequestOrderAndMovesSessionToReflection() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.canSaveReflection()).willReturn(true);
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest(
            "  우리 가족  ",
            List.of(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM),
            "  다 같이 있어서 좋았어  ",
            false);

    DrawingReflectionResponse response = service.save(DRAWING_SESSION_ID, request);

    verify(accessValidator).requireDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID);
    verify(emotionRepository).deleteAllByDrawingSessionId(DRAWING_SESSION_ID);
    @SuppressWarnings("unchecked")
    ArgumentCaptor<List<DrawingSessionEmotion>> emotions = ArgumentCaptor.forClass(List.class);
    verify(emotionRepository).saveAll(emotions.capture());
    assertThat(emotions.getValue())
        .extracting(DrawingSessionEmotion::getEmotionCode)
        .containsExactly(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM);
    assertThat(emotions.getValue())
        .extracting(DrawingSessionEmotion::getSelectionOrder)
        .containsExactly(0, 1);
    verify(drawingSession).saveReflection("우리 가족", "다 같이 있어서 좋았어");
    assertThat(response.drawingSessionId()).isEqualTo(DRAWING_SESSION_ID);
    assertThat(response.currentStage()).isEqualTo(DrawingStage.REFLECTION);
    assertThat(response.selectedEmotions())
        .containsExactly(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM);
    assertThat(response.skipped()).isFalse();
  }

  @Test
  void savesSkippedReflectionWithoutEmotionRows() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.canSaveReflection()).willReturn(true);
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest("제목", List.of(), null, true);

    DrawingReflectionResponse response = service.save(DRAWING_SESSION_ID, request);

    verify(emotionRepository).deleteAllByDrawingSessionId(DRAWING_SESSION_ID);
    verifyNoInteractionsWithEmotionSave();
    verify(drawingSession).saveReflection("제목", null);
    assertThat(response.selectedEmotions()).isEmpty();
    assertThat(response.skipped()).isTrue();
  }

  @Test
  void rejectsEmptySelectionWhenNotSkipped() {
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest(null, List.of(), null, false);

    assertInvalidRequest(request);
  }

  @Test
  void rejectsUnknownCombinedWithAnotherEmotion() {
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest(
            null, List.of(DrawingEmotionCode.UNKNOWN, DrawingEmotionCode.SAD), null, false);

    assertInvalidRequest(request);
  }

  @Test
  void rejectsEmotionOrExpressionWhenSkipped() {
    assertInvalidRequest(
        new SaveDrawingReflectionRequest(null, List.of(DrawingEmotionCode.HAPPY), null, true));
    assertInvalidRequest(new SaveDrawingReflectionRequest(null, List.of(), "직접 표현", true));
  }

  @Test
  void stopsBeforeSessionLookupWhenGuardianHasNoAccess() {
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest(null, List.of(DrawingEmotionCode.HAPPY), null, false);
    doThrow(new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
        .when(accessValidator)
        .requireDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID);

    assertThatThrownBy(() -> service.save(DRAWING_SESSION_ID, request))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));

    verifyNoInteractions(drawingSessionRepository, emotionRepository);
  }

  @Test
  void rejectsSessionOutsideConversingOrReflectionStage() {
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.canSaveReflection()).willReturn(false);
    SaveDrawingReflectionRequest request =
        new SaveDrawingReflectionRequest(null, List.of(DrawingEmotionCode.HAPPY), null, false);

    assertThatThrownBy(() -> service.save(DRAWING_SESSION_ID, request))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(DrawingErrorCode.DRAWING_REFLECTION_NOT_ALLOWED));

    verifyNoInteractions(emotionRepository);
  }

  private void assertInvalidRequest(SaveDrawingReflectionRequest request) {
    assertThatThrownBy(() -> service.save(DRAWING_SESSION_ID, request))
        .isInstanceOf(BusinessException.class)
        .satisfies(
            exception ->
                assertThat(((BusinessException) exception).getErrorCode())
                    .isEqualTo(DrawingErrorCode.DRAWING_REFLECTION_INVALID));
    verifyNoInteractions(drawingSessionRepository, emotionRepository);
  }

  private void verifyNoInteractionsWithEmotionSave() {
    verify(emotionRepository).saveAll(List.of());
  }
}
