package com.ssafy.b209.drawing.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.drawing.dto.request.SaveDrawingDraftRequest;
import com.ssafy.b209.drawing.dto.response.DrawingDraftResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Component;

/**
 * Redis에서 Draft 저장 요청을 선점하고 최초 성공 응답을 재생한다.
 *
 * <p>Fingerprint는 preview 전체 Byte와 canonical canvasState를 길이 구분자와 함께 포함한다. Redis 장애 시 기존 DB
 * sequence·unique guard가 최종 방어하도록 저장 요청을 계속 처리한다.
 */
@Component
public class DrawingDraftIdempotencyStore {

  private static final Logger log = LoggerFactory.getLogger(DrawingDraftIdempotencyStore.class);

  private final DrawingDraftIdempotencyRedisOperations redisOperations;
  private final DrawingDraftIdempotencyProperties properties;
  private final ObjectMapper objectMapper;

  DrawingDraftIdempotencyStore(
      DrawingDraftIdempotencyRedisOperations redisOperations,
      DrawingDraftIdempotencyProperties properties,
      ObjectMapper objectMapper) {
    this.redisOperations = redisOperations;
    this.properties = properties;
    this.objectMapper = objectMapper;
  }

  /**
   * 동일 사용자·세션·키의 최초 Draft 저장 결과를 반환한다.
   *
   * @param guardianUserId 인증 보호자 ID
   * @param drawingSessionId Draft 대상 세션 ID
   * @param idempotencyKey 재시도를 식별하는 Header 값
   * @param previewBytes 미리보기 실제 Byte 전체
   * @param canvasState 복구 기준 Metadata
   * @param save 최초 저장 함수
   * @return 최초 저장 또는 Redis에서 복원한 동일 응답
   */
  public DrawingDraftResponse execute(
      Long guardianUserId,
      Long drawingSessionId,
      String idempotencyKey,
      byte[] previewBytes,
      SaveDrawingDraftRequest canvasState,
      Supplier<DrawingDraftResponse> save) {
    validateKey(idempotencyKey);
    String redisKey =
        "idempotency:"
            + guardianUserId
            + ":PUT:drawing-sessions:"
            + drawingSessionId
            + ":draft:"
            + idempotencyKey;
    String fingerprint = fingerprint(previewBytes, canvasState);
    try {
      return executeWithRedis(redisKey, fingerprint, save);
    } catch (DataAccessException exception) {
      log.warn("Draft idempotency Redis unavailable; DB sequence guard remains active");
      return save.get();
    }
  }

  private DrawingDraftResponse executeWithRedis(
      String redisKey, String fingerprint, Supplier<DrawingDraftResponse> save) {
    DrawingDraftIdempotencyClaim claim =
        redisOperations.claim(redisKey, fingerprint, properties.getProcessingTtl());
    if (claim.status() == DrawingDraftIdempotencyClaimStatus.REUSED) {
      throw new BusinessException(DrawingErrorCode.DRAFT_IDEMPOTENCY_KEY_REUSED);
    }
    if (claim.status() == DrawingDraftIdempotencyClaimStatus.COMPLETED) {
      return readResponse(claim.responseJson());
    }
    if (claim.status() == DrawingDraftIdempotencyClaimStatus.PROCESSING) {
      return waitForCompletion(redisKey, fingerprint);
    }
    try {
      DrawingDraftResponse response = save.get();
      try {
        redisOperations.complete(
            redisKey, fingerprint, writeResponse(response), properties.getCompletedTtl());
      } catch (DataAccessException exception) {
        log.warn("Draft 저장 성공 응답을 Redis에 보존하지 못했습니다. DB sequence guard는 유지됩니다.");
      }
      return response;
    } catch (RuntimeException exception) {
      try {
        redisOperations.release(redisKey, fingerprint);
      } catch (DataAccessException releaseException) {
        log.warn("실패한 Draft 멱등성 선점을 Redis에서 해제하지 못했습니다.");
      }
      throw exception;
    }
  }

  private DrawingDraftResponse waitForCompletion(String redisKey, String fingerprint) {
    Instant deadline = Instant.now().plus(properties.getProcessingWait());
    while (Instant.now().isBefore(deadline)) {
      pause();
      DrawingDraftIdempotencyClaim claim =
          redisOperations.claim(redisKey, fingerprint, properties.getProcessingTtl());
      if (claim.status() == DrawingDraftIdempotencyClaimStatus.COMPLETED) {
        return readResponse(claim.responseJson());
      }
      if (claim.status() == DrawingDraftIdempotencyClaimStatus.REUSED) {
        throw new BusinessException(DrawingErrorCode.DRAFT_IDEMPOTENCY_KEY_REUSED);
      }
      if (claim.status() == DrawingDraftIdempotencyClaimStatus.CLAIMED) {
        throw new BusinessException(DrawingErrorCode.DRAFT_SAVE_IN_PROGRESS);
      }
    }
    throw new BusinessException(DrawingErrorCode.DRAFT_SAVE_IN_PROGRESS);
  }

  private String fingerprint(byte[] previewBytes, SaveDrawingDraftRequest canvasState) {
    try {
      byte[] stateBytes = objectMapper.writeValueAsBytes(canvasState);
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      digest.update(ByteBuffer.allocate(Long.BYTES).putLong(previewBytes.length).array());
      digest.update(previewBytes);
      digest.update(ByteBuffer.allocate(Long.BYTES).putLong(stateBytes.length).array());
      digest.update(stateBytes);
      return HexFormat.of().formatHex(digest.digest());
    } catch (JsonProcessingException | NoSuchAlgorithmException exception) {
      throw new IllegalStateException("Draft request fingerprint cannot be calculated", exception);
    }
  }

  private String writeResponse(DrawingDraftResponse response) {
    try {
      return objectMapper.writeValueAsString(response);
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException("Draft response cannot be stored", exception);
    }
  }

  private DrawingDraftResponse readResponse(String responseJson) {
    try {
      return objectMapper.readValue(responseJson, DrawingDraftResponse.class);
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException("Stored Draft response cannot be read", exception);
    }
  }

  private void validateKey(String idempotencyKey) {
    if (idempotencyKey == null || idempotencyKey.isBlank()) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    }
    if (!idempotencyKey.matches("[A-Za-z0-9._:-]{8,100}")) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    }
  }

  private void pause() {
    try {
      Thread.sleep(properties.getPollingInterval().toMillis());
    } catch (InterruptedException exception) {
      Thread.currentThread().interrupt();
      throw new BusinessException(DrawingErrorCode.DRAFT_SAVE_IN_PROGRESS);
    }
  }
}
