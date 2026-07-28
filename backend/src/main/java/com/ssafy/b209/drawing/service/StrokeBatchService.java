package com.ssafy.b209.drawing.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.StrokeBatch;
import com.ssafy.b209.drawing.domain.StrokeEvent;
import com.ssafy.b209.drawing.domain.StrokeEventPoint;
import com.ssafy.b209.drawing.dto.request.SaveStrokeBatchRequest;
import com.ssafy.b209.drawing.dto.request.StrokeEventRequest;
import com.ssafy.b209.drawing.dto.request.StrokePointRequest;
import com.ssafy.b209.drawing.dto.response.StrokeBatchResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.StrokeBatchRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.HexFormat;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 진행 중인 Canvas 그림 활동의 행동 이벤트를 순서화된 배치로 저장한다.
 *
 * <p>세션 잠금과 배치 순번·payload checksum을 조합해 같은 요청은 기존 결과로 응답하고 내용이 다른 순번 재사용은 거부한다.
 */
@Service
public class StrokeBatchService {

  private static final int MAX_PAYLOAD_BYTES = 1024 * 1024;
  private static final int MAX_POINTS_PER_BATCH = 20_000;

  private final DrawingSessionRepository drawingSessionRepository;
  private final StrokeBatchRepository strokeBatchRepository;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final ObjectMapper objectMapper;
  private final Clock clock;

  /**
   * Stroke 배치 저장에 필요한 인증·세션·직렬화 의존성을 구성한다.
   *
   * @param drawingSessionRepository 세션 잠금 Repository
   * @param strokeBatchRepository 정규화된 Stroke 저장 Repository
   * @param currentUserResolver 인증 사용자 Resolver
   * @param accessValidator 보호자와 그림 활동의 연결 검증기
   * @param objectMapper checksum용 표준 JSON 직렬화기
   * @param clock 서버 수신 시각
   */
  public StrokeBatchService(
      DrawingSessionRepository drawingSessionRepository,
      StrokeBatchRepository strokeBatchRepository,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      ObjectMapper objectMapper,
      Clock clock) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.strokeBatchRepository = strokeBatchRepository;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.objectMapper = objectMapper;
    this.clock = clock;
  }

  /**
   * 유효한 Stroke 배치를 세 테이블에 하나의 Transaction으로 저장한다.
   *
   * @param drawingSessionId 그림 활동 식별자
   * @param request 순서화된 이벤트와 행동 지표
   * @return 저장 결과와 신규 생성 여부
   * @throws BusinessException 권한·상태·순서·크기 또는 멱등 규칙을 위반한 경우
   */
  @Transactional
  public StrokeBatchSaveResult save(Long drawingSessionId, SaveStrokeBatchRequest request) {
    validateSequences(request);
    validatePointCount(request);
    byte[] payload = serialize(request);
    if (payload.length > MAX_PAYLOAD_BYTES) {
      throw new BusinessException(DrawingErrorCode.STROKE_BATCH_PAYLOAD_TOO_LARGE);
    }
    String checksum = sha256(payload);
    Long userId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(userId, drawingSessionId);
    DrawingSession session =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    if (!session.canAcceptStrokeBatch()) {
      throw new BusinessException(DrawingErrorCode.STROKE_BATCH_NOT_ALLOWED);
    }

    var existing =
        strokeBatchRepository.findByDrawingSession_IdAndBatchSequence(
            drawingSessionId, request.batchSequence());
    if (existing.isPresent()) {
      StrokeBatch batch = existing.orElseThrow();
      if (!batch.getPayloadChecksumSha256().equals(checksum)) {
        throw new BusinessException(DrawingErrorCode.STROKE_BATCH_CONFLICT);
      }
      return new StrokeBatchSaveResult(toResponse(batch), false);
    }

    LocalDateTime receivedAt = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    StrokeBatch batch = createBatch(session, request, checksum, receivedAt);
    try {
      return new StrokeBatchSaveResult(toResponse(strokeBatchRepository.saveAndFlush(batch)), true);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(DrawingErrorCode.STROKE_BATCH_CONFLICT, exception);
    }
  }

  private void validatePointCount(SaveStrokeBatchRequest request) {
    int pointCount = 0;
    for (StrokeEventRequest event : request.events()) {
      pointCount += event.points().size();
      if (pointCount > MAX_POINTS_PER_BATCH) {
        throw new BusinessException(DrawingErrorCode.STROKE_BATCH_POINT_LIMIT_EXCEEDED);
      }
    }
  }

  private StrokeBatch createBatch(
      DrawingSession session,
      SaveStrokeBatchRequest request,
      String checksum,
      LocalDateTime receivedAt) {
    StrokeBatch batch =
        StrokeBatch.create(
            session,
            request.batchSequence(),
            request.firstEventSequence(),
            request.lastEventSequence(),
            checksum,
            request.metrics().undoCountDelta(),
            request.metrics().redoCountDelta(),
            request.metrics().eraseCountDelta(),
            request.metrics().pauseDurationMsDelta(),
            request.clientCreatedAt().withOffsetSameInstant(ZoneOffset.UTC).toLocalDateTime(),
            receivedAt);
    for (StrokeEventRequest eventRequest : request.events()) {
      StrokeEvent event =
          StrokeEvent.create(
              eventRequest.sequence(),
              eventRequest.eventType(),
              eventRequest.tool(),
              eventRequest.color(),
              eventRequest.width(),
              eventRequest.pressure(),
              receivedAt);
      int pointSequence = 0;
      for (StrokePointRequest point : eventRequest.points()) {
        event.addPoint(
            StrokeEventPoint.create(
                pointSequence++, point.x(), point.y(), point.t(), point.pressure()));
      }
      batch.addEvent(event);
    }
    return batch;
  }

  private void validateSequences(SaveStrokeBatchRequest request) {
    if (request == null || request.events() == null || request.events().isEmpty()) {
      throw new BusinessException(DrawingErrorCode.STROKE_BATCH_INVALID);
    }
    long previous = 0;
    for (StrokeEventRequest event : request.events()) {
      if (event == null || event.sequence() <= previous) {
        throw new BusinessException(DrawingErrorCode.STROKE_BATCH_INVALID);
      }
      long pointTime = -1;
      if (event.points() == null
          || ("STROKE".equals(event.eventType()) && event.points().isEmpty())) {
        throw new BusinessException(DrawingErrorCode.STROKE_BATCH_INVALID);
      }
      for (StrokePointRequest point : event.points()) {
        if (point == null || point.t() < pointTime) {
          throw new BusinessException(DrawingErrorCode.STROKE_BATCH_INVALID);
        }
        pointTime = point.t();
      }
      previous = event.sequence();
    }
    if (request.firstEventSequence() != request.events().getFirst().sequence()
        || request.lastEventSequence() != request.events().getLast().sequence()) {
      throw new BusinessException(DrawingErrorCode.STROKE_BATCH_INVALID);
    }
  }

  private byte[] serialize(SaveStrokeBatchRequest request) {
    try {
      return objectMapper.writeValueAsBytes(request);
    } catch (JsonProcessingException exception) {
      throw new BusinessException(DrawingErrorCode.STROKE_BATCH_INVALID, exception);
    }
  }

  private String sha256(byte[] payload) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(payload));
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 algorithm is unavailable", exception);
    }
  }

  private StrokeBatchResponse toResponse(StrokeBatch batch) {
    return new StrokeBatchResponse(
        batch.getId(),
        batch.getBatchSequence(),
        batch.getEventCount(),
        batch.getLastEventSequence(),
        batch.getReceivedAt().toInstant(ZoneOffset.UTC));
  }
}
