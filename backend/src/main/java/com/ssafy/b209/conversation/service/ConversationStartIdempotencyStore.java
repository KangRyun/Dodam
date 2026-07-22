package com.ssafy.b209.conversation.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.dto.StartConversationRequest;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import java.net.URI;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;

/**
 * Redis 공유 저장소에서 대화 시작의 최초 HTTP 응답을 원자적으로 보관하고 재생한다.
 *
 * <p>Redis 선점 또는 완료 응답 저장이 실패하면 요청을 차단하지 않고 DB UNIQUE 제약이 중복 생성을 최종 방어한다. 이 경우 최초 응답 재생은 보장하지 않는다.
 */
@Component
public class ConversationStartIdempotencyStore {
  private static final Logger log =
      LoggerFactory.getLogger(ConversationStartIdempotencyStore.class);
  private static final String METHOD = "POST";

  private final ConversationIdempotencyRedisOperations redisOperations;
  private final ObjectMapper objectMapper;
  private final ConversationStartIdempotencyProperties properties;

  ConversationStartIdempotencyStore(
      ConversationIdempotencyRedisOperations redisOperations,
      ObjectMapper objectMapper,
      ConversationStartIdempotencyProperties properties) {
    this.redisOperations = redisOperations;
    this.objectMapper = objectMapper;
    this.properties = properties;
  }

  /**
   * 동일 사용자·POST URI·Idempotency-Key의 최초 HTTP 응답을 Redis에 저장하거나 저장된 응답을 반환한다.
   *
   * <p>같은 Body는 완료된 최초 상태 코드·Body·Location을 재생한다. 다른 Body는 409을 발생시키고, 처리 중이면 설정된 시간만큼 대기한 뒤에도 완료되지
   * 않았을 때 409을 발생시킨다. 예상하지 못한 서버 오류는 5분간만 저장한다.
   *
   * @param guardianUserId 현재 보호자 식별자
   * @param uri 멱등성 범위에 포함할 외부 API URI
   * @param idempotencyKey 재전송을 식별하는 Header 값
   * @param request fingerprint를 계산할 요청 Body
   * @param responseSupplier 최초 요청의 HTTP 상태·Body·Location을 만드는 함수
   * @return 최초 또는 Redis에서 재생한 HTTP 응답
   * @throws BusinessException 키가 다른 Body에 재사용됐거나 처리 중 대기가 만료된 경우
   */
  public ResponseEntity<?> execute(
      Long guardianUserId,
      String uri,
      String idempotencyKey,
      StartConversationRequest request,
      Supplier<ResponseEntity<?>> responseSupplier) {
    if (idempotencyKey == null || idempotencyKey.isBlank()) {
      throw new BusinessException(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED);
    }
    String redisKey = redisKey(guardianUserId, uri, idempotencyKey);
    String fingerprint = fingerprint(request);
    try {
      return executeWithRedis(redisKey, fingerprint, responseSupplier);
    } catch (DataAccessException exception) {
      log.warn(
          "Redis idempotency store unavailable; DB unique constraint remains the duplicate guard");
      return responseSupplier.get();
    }
  }

  private ResponseEntity<?> executeWithRedis(
      String redisKey, String fingerprint, Supplier<ResponseEntity<?>> responseSupplier) {
    IdempotencyClaim claim =
        redisOperations.claim(redisKey, fingerprint, properties.getProcessingTtl());
    if (claim.status() == IdempotencyClaimStatus.REUSED) {
      throw new BusinessException(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED);
    }
    if (claim.status() == IdempotencyClaimStatus.COMPLETED) {
      return replay(claim.response());
    }
    if (claim.status() == IdempotencyClaimStatus.PROCESSING) {
      return waitForCompletion(redisKey, fingerprint);
    }
    return processClaimedRequest(redisKey, fingerprint, responseSupplier);
  }

  private ResponseEntity<?> waitForCompletion(String redisKey, String fingerprint) {
    Instant deadline = Instant.now().plus(properties.getProcessingWait());
    while (Instant.now().isBefore(deadline)) {
      pause(properties.getPollingInterval());
      IdempotencyClaim claim =
          redisOperations.claim(redisKey, fingerprint, properties.getProcessingTtl());
      if (claim.status() == IdempotencyClaimStatus.REUSED) {
        throw new BusinessException(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED);
      }
      if (claim.status() == IdempotencyClaimStatus.COMPLETED) {
        return replay(claim.response());
      }
      if (claim.status() == IdempotencyClaimStatus.CLAIMED) {
        throw new BusinessException(ConversationStartErrorCode.CONVERSATION_START_CONFLICT);
      }
    }
    throw new BusinessException(ConversationStartErrorCode.CONVERSATION_START_CONFLICT);
  }

  private ResponseEntity<?> processClaimedRequest(
      String redisKey, String fingerprint, Supplier<ResponseEntity<?>> responseSupplier) {
    ResponseEntity<?> response;
    try {
      response = responseSupplier.get();
    } catch (RuntimeException exception) {
      log.error(
          "Conversation start failed after Redis idempotency claim: type={}",
          exception.getClass().getName());
      response =
          ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
              .body(ApiErrorResponse.of(CommonErrorCode.INTERNAL_SERVER_ERROR));
    }
    StoredConversationHttpResponse storedResponse = snapshot(response);
    Duration ttl =
        response.getStatusCode().is5xxServerError()
            ? properties.getFailureTtl()
            : properties.getCompletedTtl();
    try {
      redisOperations.complete(redisKey, fingerprint, storedResponse, ttl);
    } catch (DataAccessException exception) {
      log.warn(
          "Conversation start response was not saved to Redis; DB unique constraint remains active");
    }
    return response;
  }

  private ResponseEntity<String> replay(StoredConversationHttpResponse response) {
    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_JSON);
    if (response.location() != null) {
      headers.setLocation(URI.create(response.location()));
    }
    return ResponseEntity.status(response.status()).headers(headers).body(response.body());
  }

  private StoredConversationHttpResponse snapshot(ResponseEntity<?> response) {
    try {
      String location =
          response.getHeaders().getLocation() == null
              ? null
              : response.getHeaders().getLocation().toString();
      return new StoredConversationHttpResponse(
          response.getStatusCode().value(),
          location,
          objectMapper.writeValueAsString(response.getBody()));
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException("Conversation HTTP response cannot be serialized", exception);
    }
  }

  private String redisKey(Long guardianUserId, String uri, String idempotencyKey) {
    return "idempotency:" + guardianUserId + ':' + METHOD + ':' + uri + ':' + idempotencyKey;
  }

  private String fingerprint(StartConversationRequest request) {
    try {
      byte[] body = objectMapper.writeValueAsBytes(request);
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(body));
    } catch (JsonProcessingException | NoSuchAlgorithmException exception) {
      throw new IllegalStateException(
          "Conversation request fingerprint cannot be calculated", exception);
    }
  }

  private void pause(Duration duration) {
    try {
      Thread.sleep(duration.toMillis());
    } catch (InterruptedException exception) {
      Thread.currentThread().interrupt();
      throw new BusinessException(ConversationStartErrorCode.CONVERSATION_START_CONFLICT);
    }
  }
}
