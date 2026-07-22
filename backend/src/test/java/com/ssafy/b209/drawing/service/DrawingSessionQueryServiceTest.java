package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.response.ActiveDrawingSessionResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DrawingSessionQueryServiceTest {

  private static final Long CHILD_ID = 3L;
  private static final Long SESSION_ID = 10L;
  private static final LocalDateTime STARTED_AT = LocalDateTime.of(2026, 7, 22, 4, 0);
  private static final LocalDateTime CLIENT_SAVED_AT = LocalDateTime.of(2026, 7, 22, 4, 5);
  private static final LocalDateTime SAVED_AT = LocalDateTime.of(2026, 7, 22, 4, 5, 1);

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private DrawingSession session;
  @Mock private DrawingSession duplicateSession;
  @Mock private DrawingAsset draft;
  @Mock private Child child;
  @Mock private DrawingType drawingType;

  private DrawingSessionQueryService service;

  @BeforeEach
  void setUp() {
    service = new DrawingSessionQueryService(drawingSessionRepository, drawingAssetRepository);
  }

  @Test
  void returnsTheActiveSessionAndItsLatestDraftMetadata() {
    given(drawingSessionRepository.findActiveSessionsByChildId(CHILD_ID))
        .willReturn(List.of(session));
    given(session.getId()).willReturn(SESSION_ID);
    given(session.getChild()).willReturn(child);
    given(child.getId()).willReturn(CHILD_ID);
    given(session.getDrawingType()).willReturn(drawingType);
    given(drawingType.getId()).willReturn(7L);
    given(drawingType.getCode()).willReturn("HOUSE");
    given(drawingType.getName()).willReturn("집");
    given(session.getInputMethod()).willReturn(DrawingInputMethod.CANVAS);
    given(session.getSessionStatus()).willReturn(DrawingSessionStatus.IN_PROGRESS);
    given(session.getCurrentStage()).willReturn(DrawingStage.DRAWING);
    given(session.getStartedAt()).willReturn(STARTED_AT);
    given(drawingAssetRepository.findLatestDraft(SESSION_ID)).willReturn(Optional.of(draft));
    given(draft.getId()).willReturn(20L);
    given(draft.getAssetVersion()).willReturn(4);
    given(draft.getLastEventSequence()).willReturn(31L);
    given(draft.getMimeType()).willReturn("image/png");
    given(draft.getFileSizeBytes()).willReturn(2048L);
    given(draft.getCapturedAt()).willReturn(CLIENT_SAVED_AT);
    given(draft.getCreatedAt()).willReturn(SAVED_AT);

    ActiveDrawingSessionResponse response = service.getActiveDrawingSession(CHILD_ID);

    assertThat(response.drawingSessionId()).isEqualTo(SESSION_ID);
    assertThat(response.childId()).isEqualTo(CHILD_ID);
    assertThat(response.drawingType().drawingTypeId()).isEqualTo(7L);
    assertThat(response.drawingType().code()).isEqualTo("HOUSE");
    assertThat(response.inputMethod()).isEqualTo(DrawingInputMethod.CANVAS);
    assertThat(response.sessionStatus()).isEqualTo(DrawingSessionStatus.IN_PROGRESS);
    assertThat(response.currentStage()).isEqualTo(DrawingStage.DRAWING);
    assertThat(response.startedAt()).isEqualTo(STARTED_AT.toInstant(ZoneOffset.UTC));
    assertThat(response.latestDraft().drawingAssetId()).isEqualTo(20L);
    assertThat(response.latestDraft().assetVersion()).isEqualTo(4);
    assertThat(response.latestDraft().lastEventSequence()).isEqualTo(31L);
    assertThat(response.latestDraft().clientSavedAt())
        .isEqualTo(CLIENT_SAVED_AT.toInstant(ZoneOffset.UTC));
    assertThat(response.latestDraft().savedAt()).isEqualTo(SAVED_AT.toInstant(ZoneOffset.UTC));
    assertThat(response.latestDraft().previewUrl()).isNull();
  }

  @Test
  void returnsNullLatestDraftWhenTheActiveSessionHasNoSavedDraft() {
    given(drawingSessionRepository.findActiveSessionsByChildId(CHILD_ID))
        .willReturn(List.of(session));
    given(session.getId()).willReturn(SESSION_ID);
    given(session.getChild()).willReturn(child);
    given(child.getId()).willReturn(CHILD_ID);
    given(session.getDrawingType()).willReturn(drawingType);
    given(session.getStartedAt()).willReturn(STARTED_AT);
    given(drawingAssetRepository.findLatestDraft(SESSION_ID)).willReturn(Optional.empty());

    ActiveDrawingSessionResponse response = service.getActiveDrawingSession(CHILD_ID);

    assertThat(response.latestDraft()).isNull();
  }

  @Test
  void reportsNotFoundWithoutLookingForADraftWhenNoActiveSessionExists() {
    given(drawingSessionRepository.findActiveSessionsByChildId(CHILD_ID)).willReturn(List.of());

    assertError(
        () -> service.getActiveDrawingSession(CHILD_ID),
        DrawingErrorCode.ACTIVE_DRAWING_SESSION_NOT_FOUND);
    verifyNoInteractions(drawingAssetRepository);
  }

  @Test
  void reportsDataIntegrityFailureWithoutChoosingOneOfMultipleActiveSessions() {
    given(drawingSessionRepository.findActiveSessionsByChildId(CHILD_ID))
        .willReturn(List.of(session, duplicateSession));

    assertError(
        () -> service.getActiveDrawingSession(CHILD_ID),
        DrawingErrorCode.MULTIPLE_ACTIVE_DRAWING_SESSIONS);
    verifyNoInteractions(drawingAssetRepository);
  }

  private void assertError(Runnable invocation, DrawingErrorCode expected) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
