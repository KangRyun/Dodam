package com.ssafy.b209.drawing.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.List;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Component;

/** Redis Lua로 Draft 멱등 키의 선점·완료·실패 해제를 원자적으로 수행한다. */
@Component
class RedisDrawingDraftIdempotencyRedisOperations
    implements DrawingDraftIdempotencyRedisOperations {

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
              + "redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[3]) return 1",
          Long.class);
  private static final DefaultRedisScript<Long> RELEASE_SCRIPT =
      new DefaultRedisScript<>(
          "local current = redis.call('GET', KEYS[1]) "
              + "if not current then return 0 end "
              + "local record = cjson.decode(current) "
              + "if record.state == 'PROCESSING' and record.fingerprint == ARGV[1] then "
              + "return redis.call('DEL', KEYS[1]) end return 0",
          Long.class);

  private final StringRedisTemplate redisTemplate;
  private final ObjectMapper objectMapper;

  RedisDrawingDraftIdempotencyRedisOperations(
      StringRedisTemplate redisTemplate, ObjectMapper objectMapper) {
    this.redisTemplate = redisTemplate;
    this.objectMapper = objectMapper;
  }

  @Override
  public DrawingDraftIdempotencyClaim claim(
      String redisKey, String fingerprint, Duration processingTtl) {
    String result =
        redisTemplate.execute(
            CLAIM_SCRIPT, List.of(redisKey), fingerprint, Long.toString(processingTtl.toMillis()));
    if ("CLAIMED".equals(result)) {
      return DrawingDraftIdempotencyClaim.claimed();
    }
    if ("PROCESSING".equals(result)) {
      return DrawingDraftIdempotencyClaim.processing();
    }
    if ("REUSED".equals(result)) {
      return DrawingDraftIdempotencyClaim.reused();
    }
    if (result != null && result.startsWith(COMPLETED_PREFIX)) {
      return DrawingDraftIdempotencyClaim.completed(
          readResponse(result.substring(COMPLETED_PREFIX.length())));
    }
    throw new IllegalStateException("Unexpected Draft idempotency claim result");
  }

  @Override
  public boolean complete(
      String redisKey, String fingerprint, String responseJson, Duration completedTtl) {
    Long saved =
        redisTemplate.execute(
            COMPLETE_SCRIPT,
            List.of(redisKey),
            fingerprint,
            writeCompletedRecord(fingerprint, responseJson),
            Long.toString(completedTtl.toMillis()));
    return Long.valueOf(1L).equals(saved);
  }

  @Override
  public void release(String redisKey, String fingerprint) {
    redisTemplate.execute(RELEASE_SCRIPT, List.of(redisKey), fingerprint);
  }

  private String readResponse(String recordJson) {
    try {
      RedisDraftIdempotencyRecord record =
          objectMapper.readValue(recordJson, RedisDraftIdempotencyRecord.class);
      return record.responseJson();
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException("Stored Draft response cannot be read", exception);
    }
  }

  private String writeCompletedRecord(String fingerprint, String responseJson) {
    try {
      return objectMapper.writeValueAsString(
          new RedisDraftIdempotencyRecord(fingerprint, "COMPLETED", responseJson));
    } catch (JsonProcessingException exception) {
      throw new IllegalStateException("Draft response cannot be stored", exception);
    }
  }

  private record RedisDraftIdempotencyRecord(
      String fingerprint, String state, String responseJson) {}
}
