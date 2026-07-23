package com.ssafy.b209.conversation.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.List;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Component;

/** Redis Lua로 대화 시작 멱등성 키의 선점과 최초 응답 저장을 원자적으로 수행한다. */
@Component
class RedisConversationIdempotencyRedisOperations
    implements ConversationIdempotencyRedisOperations {
  private static final String COMPLETED_PREFIX = "COMPLETED:";
  private static final DefaultRedisScript<String> CLAIM_SCRIPT =
      new DefaultRedisScript<>(
          "local current = redis.call('GET', KEYS[1]) "
              + "if not current then "
              + "redis.call('SET', KEYS[1], cjson.encode({fingerprint=ARGV[1], state='PROCESSING'}), 'PX', ARGV[2]) "
              + "return 'CLAIMED' end "
              + "local record = cjson.decode(current) "
              + "if record.fingerprint ~= ARGV[1] then return 'REUSED' end "
              + "if record.state == 'COMPLETED' then return 'COMPLETED:' .. current end "
              + "return 'PROCESSING'",
          String.class);
  private static final DefaultRedisScript<Long> COMPLETE_SCRIPT =
      new DefaultRedisScript<>(
          "local current = redis.call('GET', KEYS[1]) "
              + "if not current then return 0 end "
              + "local record = cjson.decode(current) "
              + "if record.state ~= 'PROCESSING' or record.fingerprint ~= ARGV[1] then return 0 end "
              + "redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[3]) "
              + "return 1",
          Long.class);

  private final StringRedisTemplate redisTemplate;
  private final ObjectMapper objectMapper;

  RedisConversationIdempotencyRedisOperations(
      StringRedisTemplate redisTemplate, ObjectMapper objectMapper) {
    this.redisTemplate = redisTemplate;
    this.objectMapper = objectMapper;
  }

  /**
   * 동일 키의 fingerprint를 Lua 한 번으로 비교하고 비어 있는 키는 PROCESSING으로 선점한다.
   *
   * @param redisKey 사용자·메서드·URI·멱등 키로 구성한 Redis 키
   * @param fingerprint 결정론적으로 계산한 요청 Body fingerprint
   * @param processingTtl PROCESSING 상태 만료 시간
   * @return 선점, 기존 완료 응답, 처리 중 또는 다른 Body 재사용 결과
   */
  @Override
  public IdempotencyClaim claim(String redisKey, String fingerprint, Duration processingTtl) {
    String result =
        redisTemplate.execute(
            CLAIM_SCRIPT, List.of(redisKey), fingerprint, String.valueOf(processingTtl.toMillis()));
    if ("CLAIMED".equals(result)) {
      return IdempotencyClaim.claimed();
    }
    if ("PROCESSING".equals(result)) {
      return IdempotencyClaim.processing();
    }
    if ("REUSED".equals(result)) {
      return IdempotencyClaim.reused();
    }
    if (result != null && result.startsWith(COMPLETED_PREFIX)) {
      return IdempotencyClaim.completed(readResponse(result.substring(COMPLETED_PREFIX.length())));
    }
    throw new IllegalStateException("Unexpected Redis idempotency claim result");
  }

  /**
   * 자신이 선점한 PROCESSING 키만 최초 HTTP 응답으로 원자적으로 전환한다.
   *
   * @param redisKey 사용자·메서드·URI·멱등 키로 구성한 Redis 키
   * @param fingerprint 최초 요청 Body fingerprint
   * @param response 상태 코드·Body·Location Snapshot
   * @param responseTtl 완료 응답 보존 시간
   * @return 저장에 성공하면 {@code true}
   */
  @Override
  public boolean complete(
      String redisKey,
      String fingerprint,
      StoredConversationHttpResponse response,
      Duration responseTtl) {
    Long saved =
        redisTemplate.execute(
            COMPLETE_SCRIPT,
            List.of(redisKey),
            fingerprint,
            writeCompletedRecord(fingerprint, response),
            String.valueOf(responseTtl.toMillis()));
    return Long.valueOf(1L).equals(saved);
  }

  private StoredConversationHttpResponse readResponse(String json) {
    try {
      RedisConversationIdempotencyRecord record =
          objectMapper.readValue(json, RedisConversationIdempotencyRecord.class);
      return new StoredConversationHttpResponse(record.status(), record.location(), record.body());
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException(
          "Stored Redis idempotency response cannot be read", exception);
    }
  }

  private String writeCompletedRecord(String fingerprint, StoredConversationHttpResponse response) {
    try {
      return objectMapper.writeValueAsString(
          new RedisConversationIdempotencyRecord(
              fingerprint, "COMPLETED", response.status(), response.location(), response.body()));
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException("Redis idempotency response cannot be written", exception);
    }
  }

  private record RedisConversationIdempotencyRecord(
      String fingerprint, String state, Integer status, String location, String body) {}
}
