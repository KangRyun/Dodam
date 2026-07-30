package com.ssafy.b209.drawing.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.config.StrokeRetentionProperties;
import com.ssafy.b209.drawing.document.StrokeBatchDocument;
import com.ssafy.b209.drawing.document.StrokeEventDocument;
import com.ssafy.b209.drawing.document.StrokePointDocument;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.request.SaveStrokeBatchRequest;
import com.ssafy.b209.drawing.dto.request.StrokeEventRequest;
import com.ssafy.b209.drawing.dto.request.StrokePointRequest;
import com.ssafy.b209.drawing.dto.response.StrokeBatchResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.StrokeBatchDocumentRepository;
import com.ssafy.b209.drawing.repository.StrokeBatchIdSequenceRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 진행 중인 Canvas 그림 활동의 행동 이벤트를 순서화된 배치로 저장한다.
 *
 * <p>세션 잠금과 배치 순번·payload checksum을 조합해 같은 요청은 기존 결과로 응답하고 내용이 다른 순번 재사용은 거부한다.
 *
 * <p><b>2026-07-30 변경 (S15P11B209-365)</b>: 저장소를 MySQL 3개 테이블에서 MongoDB {@code strokes} 컬렉션으로 옮겼다.
 * 좌표 1개가 1행이던 구조가 세션당 수만~10만 행을 만들었는데, 이 데이터는 조인 없이 세션 단위로 통째 재생만 한다. <b>API 계약은 그대로다</b> — 응답
 * 필드·에러코드·멱등 규칙 어느 것도 바뀌지 않았다.
 */
@Service
public class StrokeBatchService {

  private static final int MAX_PAYLOAD_BYTES = 1024 * 1024;
  private static final int MAX_POINTS_PER_BATCH = 20_000;

  private final DrawingSessionRepository drawingSessionRepository;
  private final StrokeBatchDocumentRepository strokeBatchDocumentRepository;
  private final StrokeBatchIdSequenceRepository strokeBatchIdSequenceRepository;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final ObjectMapper objectMapper;
  private final StrokeRetentionProperties retentionProperties;
  private final Clock clock;

  /**
   * Stroke 배치 저장에 필요한 인증·세션·직렬화 의존성을 구성한다.
   *
   * @param drawingSessionRepository 세션 잠금 Repository
   * @param strokeBatchDocumentRepository Stroke 배치 문서 Repository
   * @param strokeBatchIdSequenceRepository 배치 식별자 발급 Repository
   * @param currentUserResolver 인증 사용자 Resolver
   * @param accessValidator 보호자와 그림 활동의 연결 검증기
   * @param objectMapper checksum용 표준 JSON 직렬화기
   * @param retentionProperties 보관 기간 설정
   * @param clock 서버 수신 시각
   */
  public StrokeBatchService(
      DrawingSessionRepository drawingSessionRepository,
      StrokeBatchDocumentRepository strokeBatchDocumentRepository,
      StrokeBatchIdSequenceRepository strokeBatchIdSequenceRepository,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      ObjectMapper objectMapper,
      StrokeRetentionProperties retentionProperties,
      Clock clock) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.strokeBatchDocumentRepository = strokeBatchDocumentRepository;
    this.strokeBatchIdSequenceRepository = strokeBatchIdSequenceRepository;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.objectMapper = objectMapper;
    this.retentionProperties = retentionProperties;
    this.clock = clock;
  }

  /**
   * 유효한 Stroke 배치를 MongoDB 문서 하나로 저장한다.
   *
   * <p>{@code @Transactional} 은 이제 <b>MySQL 세션 행 잠금</b>만을 위한 것이다. 같은 세션에 대한 동시 배치 저장을 직렬화해 조회-저장
   * 사이의 경합 창을 좁힌다. Mongo 쓰기는 이 Transaction에 참여하지 않으므로, 창이 완전히 닫히지는 않는다 — 최종 방어선은 {@code
   * session_batch_unique} 인덱스이며 아래 {@link DuplicateKeyException} 처리가 그 결과를 기존 계약으로 수렴시킨다.
   *
   * @param drawingSessionId 그림 활동 식별자
   * @param request 순서화된 이벤트와 행동 지표
   * @return 저장 결과와 신규 생성 여부
   * @throws BusinessException 권한·상태·순서·크기 또는 멱등 규칙을 위반한 경우
   */
  @Transactional
  public StrokeBatchSaveResult save(Long drawingSessionId, SaveStrokeBatchRequest request) {
    validateSequences(request);
    int pointCount = validatePointCount(request);
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

    Optional<StrokeBatchDocument> existing =
        strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(
            drawingSessionId, request.batchSequence());
    if (existing.isPresent()) {
      return new StrokeBatchSaveResult(
          toResponse(requireSamePayload(existing.get(), checksum)), false);
    }

    Instant receivedAt = clock.instant();
    StrokeBatchDocument document =
        createDocument(session, drawingSessionId, request, checksum, pointCount, receivedAt);
    try {
      return new StrokeBatchSaveResult(
          toResponse(strokeBatchDocumentRepository.insert(document)), true);
    } catch (DuplicateKeyException exception) {
      // 동시 요청 경합: 이 요청이 조회한 뒤 저장하기 전에 다른 요청이 같은 순번을 넣었다.
      //   먼저 저장된 문서를 기준으로 판정해 "같은 내용이면 200, 다른 내용이면 409"라는 기존 계약에 수렴시킨다.
      //   save() 가 아니라 insert() 를 쓰는 이유가 여기 있다 — save() 는 upsert 라 남의 배치를 조용히 덮어쓴다.
      StrokeBatchDocument stored =
          strokeBatchDocumentRepository
              .findBySessionIdAndBatchSeq(drawingSessionId, request.batchSequence())
              .orElseThrow(
                  () -> new BusinessException(DrawingErrorCode.STROKE_BATCH_CONFLICT, exception));
      return new StrokeBatchSaveResult(toResponse(requireSamePayload(stored, checksum)), false);
    }
  }

  /**
   * 이미 저장된 배치가 이번 요청과 같은 내용인지 확인한다.
   *
   * @param stored 같은 순번으로 이미 저장된 배치
   * @param checksum 이번 요청 payload의 checksum
   * @return 같은 내용이면 저장된 배치 그대로
   * @throws BusinessException 같은 순번에 다른 내용이 온 경우
   */
  private StrokeBatchDocument requireSamePayload(StrokeBatchDocument stored, String checksum) {
    if (!stored.payloadChecksumSha256().equals(checksum)) {
      throw new BusinessException(DrawingErrorCode.STROKE_BATCH_CONFLICT);
    }
    return stored;
  }

  private int validatePointCount(SaveStrokeBatchRequest request) {
    int pointCount = 0;
    for (StrokeEventRequest event : request.events()) {
      pointCount += event.points().size();
      if (pointCount > MAX_POINTS_PER_BATCH) {
        throw new BusinessException(DrawingErrorCode.STROKE_BATCH_POINT_LIMIT_EXCEEDED);
      }
    }
    return pointCount;
  }

  private StrokeBatchDocument createDocument(
      DrawingSession session,
      Long drawingSessionId,
      SaveStrokeBatchRequest request,
      String checksum,
      int pointCount,
      Instant receivedAt) {
    List<StrokeEventDocument> strokes = new ArrayList<>(request.events().size());
    for (StrokeEventRequest eventRequest : request.events()) {
      List<StrokePointDocument> points = new ArrayList<>(eventRequest.points().size());
      for (StrokePointRequest point : eventRequest.points()) {
        points.add(new StrokePointDocument(point.x(), point.y(), point.t(), point.pressure()));
      }
      strokes.add(
          new StrokeEventDocument(
              eventRequest.sequence(),
              eventRequest.eventType(),
              eventRequest.tool(),
              eventRequest.color(),
              eventRequest.width(),
              eventRequest.pressure(),
              List.copyOf(points)));
    }
    return new StrokeBatchDocument(
        strokeBatchIdSequenceRepository.next(),
        drawingSessionId,
        session.getChild().getId(),
        request.batchSequence(),
        request.firstEventSequence(),
        request.lastEventSequence(),
        request.events().size(),
        pointCount,
        checksum,
        request.metrics().undoCountDelta(),
        request.metrics().redoCountDelta(),
        request.metrics().eraseCountDelta(),
        request.metrics().pauseDurationMsDelta(),
        request.clientCreatedAt().toInstant(),
        receivedAt,
        receivedAt,
        receivedAt.plus(retentionProperties.retention()),
        List.copyOf(strokes));
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

  private StrokeBatchResponse toResponse(StrokeBatchDocument document) {
    return new StrokeBatchResponse(
        document.id(),
        document.batchSeq(),
        document.eventCount(),
        document.lastEventSeq(),
        document.receivedAt());
  }
}
