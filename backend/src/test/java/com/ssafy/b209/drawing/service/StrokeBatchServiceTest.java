package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.dto.request.SaveStrokeBatchRequest;
import com.ssafy.b209.drawing.dto.request.StrokeEventRequest;
import com.ssafy.b209.drawing.dto.request.StrokeMetricsRequest;
import com.ssafy.b209.drawing.dto.request.StrokePointRequest;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.StrokeBatchRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class StrokeBatchServiceTest {

  private static final Instant NOW = Instant.parse("2026-07-21T02:32:10Z");

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private StrokeBatchRepository strokeBatchRepository;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private StrokeBatchService service;

  @BeforeEach
  void setUp() {
    service =
        new StrokeBatchService(
            drawingSessionRepository,
            strokeBatchRepository,
            currentUserResolver,
            accessValidator,
            new ObjectMapper().findAndRegisterModules(),
            Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void storesAValidatedBatchWithNormalizedEventsAndPoints() {
    DrawingSession session = canvasSession();
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(drawingSessionRepository.findNotDeletedByIdForUpdate(100L))
        .thenReturn(Optional.of(session));
    when(strokeBatchRepository.findByDrawingSession_IdAndBatchSequence(100L, 3))
        .thenReturn(Optional.empty());
    when(strokeBatchRepository.saveAndFlush(any()))
        .thenAnswer(invocation -> invocation.getArgument(0));

    StrokeBatchSaveResult result = service.save(100L, request(101, 101));

    assertThat(result.created()).isTrue();
    assertThat(result.response().acceptedEventCount()).isEqualTo(1);
    assertThat(result.response().lastEventSequence()).isEqualTo(101);
    assertThat(result.response().receivedAt()).isEqualTo(NOW);
  }

  @Test
  void rejectsAnInconsistentSequenceRangeBeforeAuthentication() {
    assertThatThrownBy(() -> service.save(100L, request(100, 101)))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(DrawingErrorCode.STROKE_BATCH_INVALID);
    verifyNoInteractions(currentUserResolver, drawingSessionRepository, strokeBatchRepository);
  }

  @Test
  void rejectsStrokeStorageForAnUploadSession() {
    DrawingSession session =
        DrawingSession.start(
            child(),
            drawingType(),
            DrawingInputMethod.UPLOAD,
            NOW.atOffset(ZoneOffset.UTC).toLocalDateTime(),
            "stroke-upload-session");
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(drawingSessionRepository.findNotDeletedByIdForUpdate(100L))
        .thenReturn(Optional.of(session));

    assertThatThrownBy(() -> service.save(100L, request(101, 101)))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(DrawingErrorCode.STROKE_BATCH_NOT_ALLOWED);
  }

  private SaveStrokeBatchRequest request(long first, long last) {
    return new SaveStrokeBatchRequest(
        3,
        first,
        last,
        OffsetDateTime.parse("2026-07-21T11:32:10.120+09:00"),
        List.of(
            new StrokeEventRequest(
                101,
                "STROKE",
                "PEN",
                "#FFCC00",
                BigDecimal.valueOf(8),
                null,
                List.of(
                    new StrokePointRequest(
                        BigDecimal.valueOf(0.18), BigDecimal.valueOf(0.42), 0, null),
                    new StrokePointRequest(
                        BigDecimal.valueOf(0.19), BigDecimal.valueOf(0.43), 16, null)))),
        new StrokeMetricsRequest(1, 0, 2, 3200));
  }

  private DrawingSession canvasSession() {
    return DrawingSession.start(
        child(),
        drawingType(),
        DrawingInputMethod.CANVAS,
        NOW.atOffset(ZoneOffset.UTC).toLocalDateTime(),
        "stroke-canvas-session");
  }

  private Child child() {
    return ChildFixture.create(
        null,
        LocalDate.of(2020, 7, 21),
        ChildTutorialStatus.NOT_STARTED,
        ChildProfileStatus.ACTIVE,
        null);
  }

  private DrawingType drawingType() {
    return DrawingTypeFixture.create(
        null, "FREE_DRAWING", "자유화", DrawingTypeSelectableBy.BOTH, 3, 12, true);
  }
}
