package com.ssafy.b209.conversation.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.global.response.ErrorCode;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;

/** Redis에서 다음 질문 생성의 최초 HTTP 응답을 보관하고 같은 요청을 재생한다. */
@Component
public class ConversationQuestionIdempotencyStore {
  private static final Logger log =
      LoggerFactory.getLogger(ConversationQuestionIdempotencyStore.class);
  private final ConversationIdempotencyRedisOperations redisOperations;
  private final ObjectMapper objectMapper;
  private final ConversationStartIdempotencyProperties properties;

  /**
   * Redis 멱등성 처리 의존성을 생성한다.
   *
   * @param redisOperations Lua 선점·완료 저장 경계
   * @param objectMapper fingerprint·응답 직렬화 도구
   * @param properties 282와 공유하는 TTL·대기 설정
   */
  public ConversationQuestionIdempotencyStore(
      ConversationIdempotencyRedisOperations redisOperations,
      ObjectMapper objectMapper,
      ConversationStartIdempotencyProperties properties) {
    this.redisOperations = redisOperations;
    this.objectMapper = objectMapper;
    this.properties = properties;
  }

  /**
   * 같은 보호자·URI·키·Body의 최초 질문 응답을 저장하거나 완료 응답을 재생한다.
   *
   * @param guardianUserId 보호자 식별자
   * @param uri 외부 API URI
   * @param idempotencyKey 재전송 식별 Header
   * @param request fingerprint 대상 요청
   * @param responseSupplier 최초 질문 생성 HTTP 응답 함수
   * @return 최초 또는 재생된 응답
   * @throws BusinessException 키 누락·공백이면 공통 400 입력 오류, 다른 Body 재사용 또는 처리 중 대기 만료면 409인 경우
   */
  public ResponseEntity<?> execute(
      Long guardianUserId,
      String uri,
      String idempotencyKey,
      Object request,
      Supplier<ResponseEntity<?>> responseSupplier) {
    return execute(
        guardianUserId,
        uri,
        idempotencyKey,
        request,
        responseSupplier,
        ConversationErrorCode.QUESTION_STORAGE_CONFLICT);
  }

  /**
   * 같은 보호자·URI·키·Body의 최초 명령 응답을 저장하거나 완료 응답을 재생한다.
   *
   * <p>질문 생성 외의 대화 명령도 동일한 Redis 원자 연산을 재사용하되, 처리 중 충돌은 각 Use Case의 공개 오류 코드로 반환한다.
   *
   * @param guardianUserId 보호자 식별자
   * @param uri 외부 API URI
   * @param idempotencyKey 재전송 식별 Header
   * @param request fingerprint 대상 요청
   * @param responseSupplier 최초 명령 HTTP 응답 함수
   * @param processingConflict 처리 중 대기 만료 시 반환할 공개 오류 코드
   * @return 최초 또는 재생된 응답
   * @throws BusinessException 키가 잘못됐거나 다른 Body에 재사용됐거나 처리 중 대기가 만료된 경우
   */
  public ResponseEntity<?> execute(
      Long guardianUserId,
      String uri,
      String idempotencyKey,
      Object request,
      Supplier<ResponseEntity<?>> responseSupplier,
      ErrorCode processingConflict) {
    if (idempotencyKey == null || idempotencyKey.isBlank()) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    String fingerprint = fingerprint(request);
    String key = "idempotency:" + guardianUserId + ":POST:" + uri + ':' + idempotencyKey;
    try {
      IdempotencyClaim claim =
          redisOperations.claim(key, fingerprint, properties.getProcessingTtl());
      if (claim.status() == IdempotencyClaimStatus.REUSED) {
        throw new BusinessException(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED);
      }
      if (claim.status() == IdempotencyClaimStatus.COMPLETED) {
        return ResponseEntity.status(claim.response().status()).body(claim.response().body());
      }
      if (claim.status() == IdempotencyClaimStatus.PROCESSING) {
        return waitForCompletion(key, fingerprint, processingConflict);
      }
      return process(key, fingerprint, responseSupplier);
    } catch (DataAccessException exception) {
      log.warn(
          "Redis question idempotency unavailable; DB UNIQUE constraint remains the final guard");
      return responseSupplier.get();
    }
  }

  private ResponseEntity<?> waitForCompletion(
      String key, String fingerprint, ErrorCode processingConflict) {
    Instant deadline = Instant.now().plus(properties.getProcessingWait());
    while (Instant.now().isBefore(deadline)) {
      try {
        Thread.sleep(properties.getPollingInterval().toMillis());
      } catch (InterruptedException exception) {
        Thread.currentThread().interrupt();
        break;
      }
      IdempotencyClaim claim =
          redisOperations.claim(key, fingerprint, properties.getProcessingTtl());
      if (claim.status() == IdempotencyClaimStatus.REUSED) {
        throw new BusinessException(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED);
      }
      if (claim.status() == IdempotencyClaimStatus.COMPLETED) {
        return ResponseEntity.status(claim.response().status()).body(claim.response().body());
      }
    }
    throw new BusinessException(processingConflict);
  }

  private ResponseEntity<?> process(
      String key, String fingerprint, Supplier<ResponseEntity<?>> responseSupplier) {
    ResponseEntity<?> response;
    try {
      response = responseSupplier.get();
    } catch (RuntimeException exception) {
      log.error(
          "Question generation failed after Redis claim: type={}", exception.getClass().getName());
      response =
          ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
              .body(ApiErrorResponse.of(CommonErrorCode.INTERNAL_SERVER_ERROR));
    }
    try {
      String body = objectMapper.writeValueAsString(response.getBody());
      Duration ttl =
          response.getStatusCode().is5xxServerError()
              ? properties.getFailureTtl()
              : properties.getCompletedTtl();
      redisOperations.complete(
          key,
          fingerprint,
          new StoredConversationHttpResponse(response.getStatusCode().value(), null, body),
          ttl);
    } catch (DataAccessException exception) {
      log.warn("Question response was not saved to Redis; DB UNIQUE constraint remains active");
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException("Question HTTP response cannot be serialized", exception);
    }
    return response;
  }

  private String fingerprint(Object request) {
    try {
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256").digest(objectMapper.writeValueAsBytes(request)));
    } catch (JsonProcessingException | NoSuchAlgorithmException exception) {
      throw new IllegalStateException(
          "Question request fingerprint cannot be calculated", exception);
    }
  }
}
