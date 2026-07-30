package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.drawing.config.StrokeRetentionProperties;
import com.ssafy.b209.drawing.document.StrokeBatchDocument;
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
import com.ssafy.b209.drawing.repository.StrokeBatchDocumentRepository;
import com.ssafy.b209.drawing.repository.StrokeBatchIdSequenceRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DuplicateKeyException;

@ExtendWith(MockitoExtension.class)
class StrokeBatchServiceTest {

  private static final Instant NOW = Instant.parse("2026-07-21T02:32:10Z");
  private static final int RETENTION_DAYS = 180;

  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private StrokeBatchDocumentRepository strokeBatchDocumentRepository;
  @Mock private StrokeBatchIdSequenceRepository strokeBatchIdSequenceRepository;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private StrokeBatchService service;

  @BeforeEach
  void setUp() {
    service =
        new StrokeBatchService(
            drawingSessionRepository,
            strokeBatchDocumentRepository,
            strokeBatchIdSequenceRepository,
            currentUserResolver,
            accessValidator,
            new ObjectMapper().findAndRegisterModules(),
            new StrokeRetentionProperties(RETENTION_DAYS),
            Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void storesAValidatedBatchWithNormalizedEventsAndPoints() {
    stubCanvasSession();

    StrokeBatchSaveResult result = service.save(100L, request(101, 101));

    assertThat(result.created()).isTrue();
    assertThat(result.response().acceptedEventCount()).isEqualTo(1);
    assertThat(result.response().lastEventSequence()).isEqualTo(101);
    assertThat(result.response().receivedAt()).isEqualTo(NOW);
  }

  @Test
  void acceptsSequenceGapsCreatedByAggregatingClientStrokeEvents() {
    stubCanvasSession();
    SaveStrokeBatchRequest request =
        new SaveStrokeBatchRequest(
            3,
            12,
            15,
            OffsetDateTime.parse("2026-07-21T11:32:10.120+09:00"),
            List.of(strokeEvent(12), strokeEvent(15)),
            new StrokeMetricsRequest(0, 0, 0, 0));

    StrokeBatchSaveResult result = service.save(100L, request);

    assertThat(result.created()).isTrue();
    assertThat(result.response().acceptedEventCount()).isEqualTo(2);
    assertThat(result.response().lastEventSequence()).isEqualTo(15);
  }

  @Test
  void acceptsAStandaloneUndoEventWithoutPoints() {
    stubCanvasSession();
    SaveStrokeBatchRequest request =
        new SaveStrokeBatchRequest(
            3,
            13,
            13,
            OffsetDateTime.parse("2026-07-21T11:32:10.120+09:00"),
            List.of(new StrokeEventRequest(13, "UNDO", null, null, null, null, List.of())),
            new StrokeMetricsRequest(1, 0, 0, 0));

    StrokeBatchSaveResult result = service.save(100L, request);

    assertThat(result.created()).isTrue();
    assertThat(result.response().acceptedEventCount()).isEqualTo(1);
    assertThat(result.response().lastEventSequence()).isEqualTo(13);
  }

  @Test
  void rejectsAnInconsistentSequenceRangeBeforeAuthentication() {
    assertThatThrownBy(() -> service.save(100L, request(100, 101)))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(DrawingErrorCode.STROKE_BATCH_INVALID);
    verifyNoInteractions(
        currentUserResolver, drawingSessionRepository, strokeBatchDocumentRepository);
  }

  @Test
  void rejectsMoreThanTwentyThousandPointsBeforeAuthentication() {
    StrokePointRequest point =
        new StrokePointRequest(BigDecimal.valueOf(0.18), BigDecimal.valueOf(0.42), 0, null);
    SaveStrokeBatchRequest oversized =
        new SaveStrokeBatchRequest(
            3,
            101,
            101,
            OffsetDateTime.parse("2026-07-21T11:32:10.120+09:00"),
            List.of(
                new StrokeEventRequest(
                    101,
                    "STROKE",
                    "PEN",
                    "#FFCC00",
                    BigDecimal.valueOf(8),
                    null,
                    Collections.nCopies(20_001, point))),
            new StrokeMetricsRequest(0, 0, 0, 0));

    assertThatThrownBy(() -> service.save(100L, oversized))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(DrawingErrorCode.STROKE_BATCH_POINT_LIMIT_EXCEEDED);
    verifyNoInteractions(
        currentUserResolver, drawingSessionRepository, strokeBatchDocumentRepository);
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

  @Test
  void assignsANumericBatchIdBecauseTheAppParsesItAsAnInteger() {
    // Flutter 앱이 json['batchId'] as int 로 파싱한다. 문자열(ObjectId)을 내려보내면 앱이 파싱에서 죽는다.
    stubCanvasSession();

    StrokeBatchSaveResult result = service.save(100L, request(101, 101));

    assertThat(result.response().batchId()).isEqualTo(501L);
  }

  @Test
  void stampsExpireAtAtTheRetentionHorizonSoTheTtlIndexCanCollectIt() {
    stubCanvasSession();

    service.save(100L, request(101, 101));

    ArgumentCaptor<StrokeBatchDocument> captor = ArgumentCaptor.forClass(StrokeBatchDocument.class);
    verify(strokeBatchDocumentRepository).insert(captor.capture());
    StrokeBatchDocument saved = captor.getValue();
    assertThat(saved.createdAt()).isEqualTo(NOW);
    assertThat(saved.expireAt()).isEqualTo(NOW.plus(RETENTION_DAYS, ChronoUnit.DAYS));
    assertThat(saved.childId()).isNull();
    assertThat(saved.sessionId()).isEqualTo(100L);
    assertThat(saved.pointCount()).isEqualTo(2);
  }

  @Test
  void returnsTheStoredBatchWhenTheSamePayloadIsResent() {
    stubCanvasSession();
    StrokeBatchSaveResult first = service.save(100L, request(101, 101));
    ArgumentCaptor<StrokeBatchDocument> captor = ArgumentCaptor.forClass(StrokeBatchDocument.class);
    verify(strokeBatchDocumentRepository).insert(captor.capture());
    when(strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(100L, 3))
        .thenReturn(Optional.of(captor.getValue()));

    StrokeBatchSaveResult second = service.save(100L, request(101, 101));

    assertThat(second.created()).isFalse();
    assertThat(second.response().batchId()).isEqualTo(first.response().batchId());
    // 재전송은 새 문서를 만들지 않는다 — insert 는 첫 저장 때의 1회뿐이다.
    verify(strokeBatchDocumentRepository).insert(any(StrokeBatchDocument.class));
  }

  @Test
  void rejectsADifferentPayloadReusingTheSameBatchSequence() {
    stubCanvasSession();
    service.save(100L, request(101, 101));
    ArgumentCaptor<StrokeBatchDocument> captor = ArgumentCaptor.forClass(StrokeBatchDocument.class);
    verify(strokeBatchDocumentRepository).insert(captor.capture());
    when(strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(100L, 3))
        .thenReturn(Optional.of(captor.getValue()));

    assertThatThrownBy(() -> service.save(100L, requestWithDifferentPayload()))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(DrawingErrorCode.STROKE_BATCH_CONFLICT);
  }

  @Test
  void convergesAConcurrentDuplicateInsertToTheStoredBatch() {
    // 조회 시점엔 없었는데 저장 직전에 다른 요청이 같은 순번을 넣은 경우.
    //   unique 인덱스가 막아 주며, 그 결과는 "같은 내용이면 200"이라는 기존 계약으로 수렴해야 한다.
    stubSessionOnly();
    StrokeBatchDocument stored = capturedDocument();
    when(strokeBatchIdSequenceRepository.next()).thenReturn(777L);
    when(strokeBatchDocumentRepository.insert(any(StrokeBatchDocument.class)))
        .thenThrow(new DuplicateKeyException("session_batch_unique"));
    when(strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(100L, 3))
        .thenReturn(Optional.empty(), Optional.of(stored));

    StrokeBatchSaveResult result = service.save(100L, request(101, 101));

    assertThat(result.created()).isFalse();
    assertThat(result.response().batchId()).isEqualTo(stored.id());
  }

  @Test
  void rejectsAConcurrentDuplicateThatCarriesADifferentPayload() {
    stubSessionOnly();
    StrokeBatchDocument stored = capturedDocument();
    when(strokeBatchIdSequenceRepository.next()).thenReturn(777L);
    when(strokeBatchDocumentRepository.insert(any(StrokeBatchDocument.class)))
        .thenThrow(new DuplicateKeyException("session_batch_unique"));
    when(strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(100L, 3))
        .thenReturn(Optional.empty(), Optional.of(stored));

    assertThatThrownBy(() -> service.save(100L, requestWithDifferentPayload()))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(DrawingErrorCode.STROKE_BATCH_CONFLICT);
  }

  @Test
  void doesNotBurnABatchIdWhenTheSequenceIsAlreadyStored() {
    stubCanvasSession();
    service.save(100L, request(101, 101));
    ArgumentCaptor<StrokeBatchDocument> captor = ArgumentCaptor.forClass(StrokeBatchDocument.class);
    verify(strokeBatchDocumentRepository).insert(captor.capture());
    when(strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(100L, 3))
        .thenReturn(Optional.of(captor.getValue()));

    service.save(100L, request(101, 101));

    verify(strokeBatchIdSequenceRepository).next();
  }

  /**
   * 첫 저장으로 만들어지는 문서를 그대로 얻는다.
   *
   * @return 저장 대상 문서
   */
  private StrokeBatchDocument capturedDocument() {
    return new StrokeBatchDocument(
        501L,
        100L,
        null,
        3,
        101,
        101,
        1,
        2,
        checksumOfDefaultRequest(),
        1,
        0,
        2,
        3200,
        OffsetDateTime.parse("2026-07-21T11:32:10.120+09:00").toInstant(),
        NOW,
        NOW,
        NOW.plus(RETENTION_DAYS, ChronoUnit.DAYS),
        List.of());
  }

  /**
   * 기본 요청 payload의 checksum을 서비스와 같은 방식으로 계산한다.
   *
   * @return 64자 소문자 Hex checksum
   */
  private String checksumOfDefaultRequest() {
    try {
      byte[] payload =
          new ObjectMapper().findAndRegisterModules().writeValueAsBytes(request(101, 101));
      return java.util.HexFormat.of()
          .formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(payload));
    } catch (Exception exception) {
      throw new IllegalStateException(exception);
    }
  }

  /**
   * 같은 배치 순번이지만 내용이 다른 요청을 만든다.
   *
   * <p>이벤트 순번은 그대로 두고 지표만 바꾼다 — 순번을 바꾸면 순서 검증(400)에 먼저 걸려 멱등 충돌(409)까지 도달하지 못한다.
   *
   * @return checksum 이 다른 유효한 요청
   */
  private SaveStrokeBatchRequest requestWithDifferentPayload() {
    return new SaveStrokeBatchRequest(
        3,
        101,
        101,
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
        new StrokeMetricsRequest(9, 0, 2, 3200));
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

  private StrokeEventRequest strokeEvent(long sequence) {
    return new StrokeEventRequest(
        sequence,
        "STROKE",
        "PEN",
        "#FFCC00",
        BigDecimal.valueOf(8),
        null,
        List.of(
            new StrokePointRequest(BigDecimal.valueOf(0.18), BigDecimal.valueOf(0.42), 0, null)));
  }

  private void stubSessionOnly() {
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(drawingSessionRepository.findNotDeletedByIdForUpdate(100L))
        .thenReturn(Optional.of(canvasSession()));
  }

  private void stubCanvasSession() {
    stubSessionOnly();
    when(strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(100L, 3))
        .thenReturn(Optional.empty());
    when(strokeBatchIdSequenceRepository.next()).thenReturn(501L);
    when(strokeBatchDocumentRepository.insert(any(StrokeBatchDocument.class)))
        .thenAnswer(invocation -> invocation.getArgument(0));
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
