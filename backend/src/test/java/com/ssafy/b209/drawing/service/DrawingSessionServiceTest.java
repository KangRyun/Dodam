package com.ssafy.b209.drawing.service;

import static com.ssafy.b209.drawing.domain.DrawingInputMethod.CANVAS;
import static com.ssafy.b209.drawing.domain.DrawingInputMethod.UPLOAD;
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
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.dto.request.CanvasConfigurationRequest;
import com.ssafy.b209.drawing.dto.request.CreateDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.CreateDrawingSessionResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.sql.SQLException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
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
class DrawingSessionServiceTest {

  private static final String KEY = "drawing-key-1234";
  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Instant NOW = Instant.parse("2026-07-21T02:30:00Z");
  private static final LocalDateTime SERVER_TIME = LocalDateTime.ofInstant(NOW, ZoneOffset.UTC);

  @Mock private ChildRepository childRepository;
  @Mock private DrawingTypeRepository drawingTypeRepository;
  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private DrawingSessionService service;
  private Child child;
  private DrawingType drawingType;

  @BeforeEach
  void setUp() {
    service =
        new DrawingSessionService(
            childRepository,
            drawingTypeRepository,
            drawingSessionRepository,
            currentUserResolver,
            accessValidator,
            Clock.fixed(NOW, ZoneOffset.UTC));
    child =
        ChildFixture.create(
            1L,
            LocalDate.of(2020, 7, 21),
            ChildTutorialStatus.NOT_STARTED,
            ChildProfileStatus.ACTIVE,
            null);
    drawingType =
        DrawingTypeFixture.create(
            2L, "FREE_DRAWING", "자유화 활동", DrawingTypeSelectableBy.BOTH, 5, 10, true);
  }

  @Test
  void rejectsUnownedChildBeforeReadingOrCreatingSession() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(new BusinessException(com.ssafy.b209.child.exception.ChildErrorCode.CHILD_NOT_FOUND))
        .given(accessValidator)
        .requireChildAccess(GUARDIAN_USER_ID, 1L);

    assertThatThrownBy(() -> service.createDrawingSession(KEY, request(CANVAS)))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(childRepository, drawingTypeRepository, drawingSessionRepository);
  }

  @Test
  void createsCanvasSessionWithServerUtcTimeAndInitialState() {
    stubSuccessfulCreation();

    CreateDrawingSessionResponse response = service.createDrawingSession(KEY, request(CANVAS));

    assertThat(response.drawingSessionId()).isEqualTo(100L);
    assertThat(response.childId()).isEqualTo(1L);
    assertThat(response.drawingType().drawingTypeId()).isEqualTo(2L);
    assertThat(response.inputMethod()).isEqualTo(CANVAS);
    assertThat(response.sessionStatus()).isEqualTo(DrawingSessionStatus.IN_PROGRESS);
    assertThat(response.currentStage()).isEqualTo(DrawingStage.DRAWING);
    assertThat(response.tutorialRequired()).isTrue();
    assertThat(response.startedAt()).isEqualTo(NOW);
  }

  @Test
  void createsUploadSessionWithoutCanvas() {
    stubSuccessfulCreation();

    CreateDrawingSessionResponse response = service.createDrawingSession(KEY, request(UPLOAD));

    assertThat(response.inputMethod()).isEqualTo(UPLOAD);
  }

  @Test
  void ignoresSuppliedCanvasForUpload() {
    stubSuccessfulCreation();
    CreateDrawingSessionRequest request =
        new CreateDrawingSessionRequest(
            1L,
            2L,
            UPLOAD,
            OffsetDateTime.parse("2026-07-21T11:30:00+09:00"),
            new CanvasConfigurationRequest(null, -1, "invalid"));

    assertThat(service.createDrawingSession(KEY, request).inputMethod()).isEqualTo(UPLOAD);
  }

  @Test
  void returnsExistingSessionForSameKeyAndCoreRequest() {
    DrawingSession existing = persistedSession(CANVAS, KEY, 55L);
    given(drawingSessionRepository.findByIdempotencyKey(KEY)).willReturn(Optional.of(existing));

    CreateDrawingSessionResponse response = service.createDrawingSession(KEY, request(CANVAS));

    assertThat(response.drawingSessionId()).isEqualTo(55L);
    verifyNoInteractions(childRepository, drawingTypeRepository);
    verify(drawingSessionRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsSameKeyWithDifferentCoreRequest() {
    DrawingSession existing = persistedSession(CANVAS, KEY, 55L);
    given(drawingSessionRepository.findByIdempotencyKey(KEY)).willReturn(Optional.of(existing));

    assertBusinessError(
        () ->
            service.createDrawingSession(
                KEY,
                new CreateDrawingSessionRequest(
                    9L,
                    2L,
                    CANVAS,
                    OffsetDateTime.parse("2026-07-21T11:30:00+09:00"),
                    validCanvas())),
        DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT);
    verify(drawingSessionRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsMissingAndInvalidIdempotencyKeys() {
    assertBusinessError(
        () -> service.createDrawingSession(null, request(CANVAS)),
        DrawingErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    assertBusinessError(
        () -> service.createDrawingSession("       ", request(CANVAS)),
        DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    assertBusinessError(
        () -> service.createDrawingSession("short", request(CANVAS)),
        DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    assertBusinessError(
        () -> service.createDrawingSession("a".repeat(101), request(CANVAS)),
        DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    assertBusinessError(
        () -> service.createDrawingSession("valid-key\n", request(CANVAS)),
        DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
  }

  @Test
  void rejectsInvalidCanvasConfigurations() {
    assertInvalidCanvas(new CanvasConfigurationRequest(0, 100, "#FFFFFF"));
    assertInvalidCanvas(new CanvasConfigurationRequest(100, 8193, "#FFFFFF"));
    assertInvalidCanvas(new CanvasConfigurationRequest(100, 100, "FFFFFF"));
  }

  @Test
  void acceptsCanvasSessionWithoutCanvasConfiguration() {
    stubSuccessfulCreation();

    CreateDrawingSessionResponse response =
        service.createDrawingSession(KEY, requestWithCanvas(null));

    assertThat(response.inputMethod()).isEqualTo(CANVAS);
    assertThat(response.currentStage()).isEqualTo(DrawingStage.DRAWING);
  }

  @Test
  void acceptsCanvasSessionWithPartialConfiguration() {
    stubSuccessfulCreation();

    CreateDrawingSessionResponse response =
        service.createDrawingSession(
            KEY, requestWithCanvas(new CanvasConfigurationRequest(1080, null, null)));

    assertThat(response.inputMethod()).isEqualTo(CANVAS);
  }

  @Test
  void rejectsMissingOrInactiveChild() {
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.empty());
    assertBusinessError(
        () -> service.createDrawingSession(KEY, request(CANVAS)), DrawingErrorCode.CHILD_NOT_FOUND);

    Child inactive =
        ChildFixture.create(
            1L,
            LocalDate.of(2020, 7, 21),
            ChildTutorialStatus.NOT_STARTED,
            ChildProfileStatus.DELETED,
            null);
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(inactive));
    assertBusinessError(
        () -> service.createDrawingSession(KEY, request(CANVAS)), DrawingErrorCode.CHILD_NOT_FOUND);
  }

  @Test
  void rejectsMissingInactiveOrAgeRestrictedDrawingType() {
    given(drawingSessionRepository.findByIdempotencyKeyForUpdate(KEY)).willReturn(Optional.empty());
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
    given(drawingTypeRepository.findById(2L)).willReturn(Optional.empty());
    assertBusinessError(
        () -> service.createDrawingSession(KEY, request(CANVAS)),
        DrawingErrorCode.DRAWING_TYPE_NOT_FOUND);

    DrawingType inactive = drawingType(5, 10, false);
    given(drawingTypeRepository.findById(2L)).willReturn(Optional.of(inactive));
    assertUnavailableType();

    given(drawingTypeRepository.findById(2L)).willReturn(Optional.of(drawingType(7, null, true)));
    assertUnavailableType();

    given(drawingTypeRepository.findById(2L)).willReturn(Optional.of(drawingType(null, 5, true)));
    assertUnavailableType();
  }

  @Test
  void rejectsExistingActiveSessionWithoutSaving() {
    given(drawingSessionRepository.findByIdempotencyKeyForUpdate(KEY)).willReturn(Optional.empty());
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
    given(drawingTypeRepository.findById(2L)).willReturn(Optional.of(drawingType));
    given(drawingSessionRepository.findActiveByChildId(1L))
        .willReturn(Optional.of(persistedSession(CANVAS, "another-key", 77L)));

    assertBusinessError(
        () -> service.createDrawingSession(KEY, request(CANVAS)),
        DrawingErrorCode.ACTIVE_DRAWING_SESSION_EXISTS);
    verify(drawingSessionRepository, never()).saveAndFlush(any());
  }

  @Test
  void mapsUnclassifiedDatabaseConflictToSafeDomainError() {
    given(drawingSessionRepository.findByIdempotencyKeyForUpdate(KEY)).willReturn(Optional.empty());
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
    given(drawingTypeRepository.findById(2L)).willReturn(Optional.of(drawingType));
    given(drawingSessionRepository.findActiveByChildId(1L)).willReturn(Optional.empty());
    given(drawingSessionRepository.saveAndFlush(any()))
        .willThrow(new DataIntegrityViolationException("internal constraint"));

    assertBusinessError(
        () -> service.createDrawingSession(KEY, request(CANVAS)),
        DrawingErrorCode.DRAWING_SESSION_CREATION_CONFLICT);
  }

  @Test
  void mapsIdempotencyUniqueConstraintToKeyConflict() {
    given(drawingSessionRepository.findByIdempotencyKeyForUpdate(KEY)).willReturn(Optional.empty());
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
    given(drawingTypeRepository.findById(2L)).willReturn(Optional.of(drawingType));
    given(drawingSessionRepository.findActiveByChildId(1L)).willReturn(Optional.empty());
    SQLException duplicateKey =
        new SQLException(
            "Duplicate entry for key 'uk_drawing_sessions_idempotency_key'", "23000", 1062);
    given(drawingSessionRepository.saveAndFlush(any()))
        .willThrow(new DataIntegrityViolationException("constraint violation", duplicateKey));

    assertBusinessError(
        () -> service.createDrawingSession(KEY, request(CANVAS)),
        DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT);
  }

  private void stubSuccessfulCreation() {
    given(drawingSessionRepository.findByIdempotencyKeyForUpdate(KEY)).willReturn(Optional.empty());
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
    given(drawingTypeRepository.findById(2L)).willReturn(Optional.of(drawingType));
    given(drawingSessionRepository.findActiveByChildId(1L)).willReturn(Optional.empty());
    given(drawingSessionRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              DrawingSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", 100L);
              return session;
            });
  }

  private CreateDrawingSessionRequest request(DrawingInputMethod inputMethod) {
    return new CreateDrawingSessionRequest(
        1L,
        2L,
        inputMethod,
        OffsetDateTime.parse("2026-07-21T11:30:00+09:00"),
        inputMethod == CANVAS ? validCanvas() : null);
  }

  private CanvasConfigurationRequest validCanvas() {
    return new CanvasConfigurationRequest(1920, 1080, "#FFFFFF");
  }

  private DrawingType drawingType(Integer min, Integer max, boolean active) {
    return DrawingTypeFixture.create(
        2L, "FREE_DRAWING", "자유화 활동", DrawingTypeSelectableBy.BOTH, min, max, active);
  }

  private DrawingSession persistedSession(
      DrawingInputMethod inputMethod, String key, long sessionId) {
    DrawingSession session =
        DrawingSession.start(child, drawingType, inputMethod, SERVER_TIME, key);
    ReflectionTestUtils.setField(session, "id", sessionId);
    return session;
  }

  private CreateDrawingSessionRequest requestWithCanvas(CanvasConfigurationRequest canvas) {
    return new CreateDrawingSessionRequest(
        1L, 2L, CANVAS, OffsetDateTime.parse("2026-07-21T11:30:00+09:00"), canvas);
  }

  private void assertInvalidCanvas(CanvasConfigurationRequest canvas) {
    assertBusinessError(
        () -> service.createDrawingSession(KEY, requestWithCanvas(canvas)),
        DrawingErrorCode.INVALID_CANVAS_CONFIGURATION);
  }

  private void assertUnavailableType() {
    assertBusinessError(
        () -> service.createDrawingSession(KEY, request(CANVAS)),
        DrawingErrorCode.DRAWING_TYPE_NOT_AVAILABLE);
  }

  private void assertBusinessError(Runnable action, DrawingErrorCode expected) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
