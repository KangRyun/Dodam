package com.ssafy.b209.conversation.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.exception.VoiceAnswerErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.function.Supplier;
import org.springframework.dao.DataAccessException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;

/** Redis Lua 선점으로 음성 업로드의 최초 HTTP 응답을 재생하는 멱등성 경계다. */
@Component
public class VoiceAnswerIdempotencyStore {
  private static final DefaultRedisScript<String> CLAIM_SCRIPT =
      new DefaultRedisScript<>(
          "local current = redis.call('GET', KEYS[1]) "
              + "if not current then redis.call('SET', KEYS[1], ARGV[1], 'PX', ARGV[2], 'NX'); return 'CLAIMED' end "
              + "local record = cjson.decode(current) "
              + "if record.fingerprint ~= ARGV[3] then return 'REUSED' end "
              + "if record.state == 'COMPLETED' then return 'COMPLETED:' .. current end "
              + "return 'PROCESSING'",
          String.class);
  private static final DefaultRedisScript<Long> COMPLETE_SCRIPT =
      new DefaultRedisScript<>(
          "local current = redis.call('GET', KEYS[1]) "
              + "if not current then return 0 end "
              + "local record = cjson.decode(current) "
              + "if record.state ~= 'PROCESSING' or record.fingerprint ~= ARGV[1] then return 0 end "
              + "redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[3]); return 1",
          Long.class);

  private final StringRedisTemplate redisTemplate;
  private final ObjectMapper objectMapper;
  private final ConversationStartIdempotencyProperties properties;

  /**
   * 282·283과 동일한 Redis TTL 설정을 공유하는 음성 멱등성 Store를 만든다.
   *
   * @param redisTemplate Lua 원자 연산 실행 도구
   * @param objectMapper 안전한 응답 Snapshot 직렬화 도구
   * @param properties processing 30초·completed 24시간·failure 5분 정책
   */
  public VoiceAnswerIdempotencyStore(
      StringRedisTemplate redisTemplate,
      ObjectMapper objectMapper,
      ConversationStartIdempotencyProperties properties) {
    this.redisTemplate = redisTemplate;
    this.objectMapper = objectMapper;
    this.properties = properties;
  }

  /**
   * checksum과 metadata fingerprint가 같은 요청을 재생하고 다른 Body 재사용은 거부한다.
   *
   * <p>Redis 장애에서는 메모리 대체나 fail-open 없이 503을 반환한다.
   *
   * @param guardianUserId JWT에서 확인한 보호자 ID
   * @param uri 공개 endpoint URI
   * @param idempotencyKey 요청 Header key
   * @param fingerprint 검증된 audio checksum과 metadata의 SHA-256
   * @param responseSupplier 최초 DB 저장 결과 생성 함수
   * @return 최초 또는 재생 HTTP 응답
   */
  public ResponseEntity<?> execute(
      Long guardianUserId,
      String uri,
      String idempotencyKey,
      String fingerprint,
      Supplier<ResponseEntity<?>> responseSupplier) {
    String key = "idempotency:" + guardianUserId + ":POST:" + uri + ':' + idempotencyKey;
    try {
      Claim claim = claim(key, fingerprint);
      if (claim.type() == ClaimType.REUSED) {
        throw new BusinessException(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED);
      }
      if (claim.type() == ClaimType.COMPLETED) {
        return ResponseEntity.status(claim.status()).body(claim.body());
      }
      if (claim.type() == ClaimType.PROCESSING) {
        return waitForCompletion(key, fingerprint);
      }
      ResponseEntity<?> response = responseSupplier.get();
      complete(key, fingerprint, response);
      return response;
    } catch (DataAccessException exception) {
      throw new BusinessException(VoiceAnswerErrorCode.IDEMPOTENCY_UNAVAILABLE, exception);
    }
  }

  private ResponseEntity<?> waitForCompletion(String key, String fingerprint) {
    Instant deadline = Instant.now().plus(properties.getProcessingWait());
    while (Instant.now().isBefore(deadline)) {
      try {
        Thread.sleep(properties.getPollingInterval().toMillis());
      } catch (InterruptedException exception) {
        Thread.currentThread().interrupt();
        break;
      }
      Claim claim = claim(key, fingerprint);
      if (claim.type() == ClaimType.REUSED) {
        throw new BusinessException(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED);
      }
      if (claim.type() == ClaimType.COMPLETED) {
        return ResponseEntity.status(claim.status()).body(claim.body());
      }
    }
    throw new BusinessException(VoiceAnswerErrorCode.IDEMPOTENCY_IN_PROGRESS);
  }

  private Claim claim(String key, String fingerprint) {
    String processing = write(new RedisRecord(fingerprint, "PROCESSING", null, null));
    String result =
        redisTemplate.execute(
            CLAIM_SCRIPT,
            List.of(key),
            processing,
            String.valueOf(properties.getProcessingTtl().toMillis()),
            fingerprint);
    if ("CLAIMED".equals(result)) return new Claim(ClaimType.CLAIMED, null, null);
    if ("PROCESSING".equals(result)) return new Claim(ClaimType.PROCESSING, null, null);
    if ("REUSED".equals(result)) return new Claim(ClaimType.REUSED, null, null);
    if (result != null && result.startsWith("COMPLETED:")) {
      RedisRecord record = read(result.substring("COMPLETED:".length()));
      return new Claim(ClaimType.COMPLETED, record.status(), readTree(record.body()));
    }
    throw new BusinessException(VoiceAnswerErrorCode.IDEMPOTENCY_UNAVAILABLE);
  }

  private void complete(String key, String fingerprint, ResponseEntity<?> response) {
    String body = writeValue(response.getBody());
    Duration ttl =
        response.getStatusCode().is5xxServerError()
            ? properties.getFailureTtl()
            : properties.getCompletedTtl();
    redisTemplate.execute(
        COMPLETE_SCRIPT,
        List.of(key),
        fingerprint,
        write(new RedisRecord(fingerprint, "COMPLETED", response.getStatusCode().value(), body)),
        String.valueOf(ttl.toMillis()));
  }

  private String write(RedisRecord record) {
    try {
      return objectMapper.writeValueAsString(record);
    } catch (JsonProcessingException exception) {
      throw new BusinessException(VoiceAnswerErrorCode.IDEMPOTENCY_UNAVAILABLE, exception);
    }
  }

  private String writeValue(Object value) {
    try {
      return objectMapper.writeValueAsString(value);
    } catch (JsonProcessingException exception) {
      throw new BusinessException(VoiceAnswerErrorCode.IDEMPOTENCY_UNAVAILABLE, exception);
    }
  }

  private RedisRecord read(String value) {
    try {
      return objectMapper.readValue(value, RedisRecord.class);
    } catch (JsonProcessingException exception) {
      throw new BusinessException(VoiceAnswerErrorCode.IDEMPOTENCY_UNAVAILABLE, exception);
    }
  }

  private JsonNode readTree(String value) {
    try {
      return objectMapper.readTree(value);
    } catch (JsonProcessingException exception) {
      throw new BusinessException(VoiceAnswerErrorCode.IDEMPOTENCY_UNAVAILABLE, exception);
    }
  }

  private enum ClaimType {
    CLAIMED,
    PROCESSING,
    COMPLETED,
    REUSED
  }

  private record Claim(ClaimType type, Integer status, JsonNode body) {}

  private record RedisRecord(String fingerprint, String state, Integer status, String body) {}
}
