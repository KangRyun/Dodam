package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.dto.request.DeleteDrawingSessionRequest;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionDeletionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DrawingSessionDeletionServiceTest {

  private static final long GUARDIAN_ID = 41L;
  private static final long SESSION_ID = 100L;
  private static final Instant NOW = Instant.parse("2026-07-24T02:00:00Z");

  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;
  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private DrawingSessionDeletionRepository deletionRepository;

  private DrawingSessionDeletionService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingSessionDeletionService(
            currentUserResolver,
            accessValidator,
            drawingSessionRepository,
            deletionRepository,
            Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void softDeletesAccessibleSessionAndSchedulesStoredFiles() {
    DrawingSession session = session();
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.of(session));

    service.delete(SESSION_ID, new DeleteDrawingSessionRequest("DELETE"));

    verify(accessValidator).requireDrawingSessionAccess(GUARDIAN_ID, SESSION_ID);
    verify(deletionRepository).scheduleStorageDeletions(SESSION_ID);
    assertThat(session.getSessionStatus()).isEqualTo(DrawingSessionStatus.DELETED);
    assertThat(session.getDeletedAt()).isEqualTo(LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
  }

  @Test
  void rejectsWrongConfirmationBeforeAuthenticationOrMutation() {
    assertError(
        () -> service.delete(SESSION_ID, new DeleteDrawingSessionRequest("delete")),
        DrawingErrorCode.DRAWING_DELETION_CONFIRMATION_MISMATCH);

    verify(currentUserResolver, never()).requireUserId();
    verify(deletionRepository, never()).scheduleStorageDeletions(SESSION_ID);
  }

  @Test
  void returnsNotFoundWhenSessionDisappearsAfterAccessValidation() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(SESSION_ID))
        .willReturn(Optional.empty());

    assertError(
        () -> service.delete(SESSION_ID, new DeleteDrawingSessionRequest("DELETE")),
        DrawingErrorCode.DRAWING_SESSION_NOT_FOUND);
  }

  private DrawingSession session() {
    return DrawingSession.start(
        ChildFixture.create(
            1L,
            LocalDate.of(2019, 1, 1),
            ChildTutorialStatus.COMPLETED,
            ChildProfileStatus.ACTIVE,
            null),
        DrawingTypeFixture.create(
            2L, "FREE_DRAWING", "자유화", DrawingTypeSelectableBy.BOTH, 4, 12, true),
        DrawingInputMethod.CANVAS,
        LocalDateTime.parse("2026-07-24T01:00:00"),
        "delete-session-key");
  }

  private void assertError(Runnable invocation, DrawingErrorCode expectedCode) {
    assertThatThrownBy(invocation::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expectedCode));
  }
}
