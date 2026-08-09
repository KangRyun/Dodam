package com.ssafy.b209.auth.service;

import java.time.Duration;
import java.util.List;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Component;

/** Redis Lua로 Refresh Token family 등록과 rotation·재사용 폐기를 원자적으로 수행한다. */
@Component
public class RedisRefreshTokenSessionStore implements RefreshTokenSessionStore {

  private static final String KEY_PREFIX = "auth:refresh:family:";
  private static final DefaultRedisScript<Long> REGISTER_SCRIPT =
      new DefaultRedisScript<>(
          "if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end "
              + "redis.call('HSET', KEYS[1], 'userId', ARGV[1], 'deviceId', ARGV[2], 'tokenHash', ARGV[3]) "
              + "redis.call('PEXPIRE', KEYS[1], ARGV[4]) return 1",
          Long.class);
  private static final DefaultRedisScript<Long> ROTATE_SCRIPT =
      new DefaultRedisScript<>(
          "if redis.call('EXISTS', KEYS[1]) == 0 then return 1 end "
              + "local userId = redis.call('HGET', KEYS[1], 'userId') "
              + "if userId ~= ARGV[1] then redis.call('DEL', KEYS[1]) return 3 end "
              + "local deviceId = redis.call('HGET', KEYS[1], 'deviceId') "
              + "if deviceId ~= ARGV[2] then return 2 end "
              + "local tokenHash = redis.call('HGET', KEYS[1], 'tokenHash') "
              + "if tokenHash ~= ARGV[3] then redis.call('DEL', KEYS[1]) return 3 end "
              + "redis.call('HSET', KEYS[1], 'tokenHash', ARGV[4]) "
              + "redis.call('PEXPIRE', KEYS[1], ARGV[5]) return 0",
          Long.class);
  private static final DefaultRedisScript<Long> REVOKE_SCRIPT =
      new DefaultRedisScript<>(
          "if redis.call('EXISTS', KEYS[1]) == 0 then return 0 end "
              + "if redis.call('HGET', KEYS[1], 'userId') ~= ARGV[1] then return 0 end "
              + "if redis.call('HGET', KEYS[1], 'deviceId') ~= ARGV[2] then return 0 end "
              + "if redis.call('HGET', KEYS[1], 'tokenHash') ~= ARGV[3] then return 0 end "
              + "redis.call('DEL', KEYS[1]) return 1",
          Long.class);
  private static final DefaultRedisScript<Long> REVOKE_ALL_SCRIPT =
      new DefaultRedisScript<>(
          "local cursor = '0' "
              + "repeat "
              + "local result = redis.call('SCAN', cursor, 'MATCH', ARGV[1], 'COUNT', 100) "
              + "cursor = result[1] "
              + "for _, key in ipairs(result[2]) do "
              + "if redis.call('HGET', key, 'userId') == ARGV[2] then redis.call('DEL', key) end "
              + "end "
              + "until cursor == '0' "
              + "return 1",
          Long.class);

  private final StringRedisTemplate redisTemplate;

  /**
   * Redis 기반 Refresh Token 저장소를 구성한다.
   *
   * @param redisTemplate Redis 명령과 Lua 실행에 사용할 Template
   */
  public RedisRefreshTokenSessionStore(StringRedisTemplate redisTemplate) {
    this.redisTemplate = redisTemplate;
  }

  @Override
  public void register(
      String familyId, Long userId, String deviceId, String tokenHash, Duration ttl) {
    Long registered =
        redisTemplate.execute(
            REGISTER_SCRIPT,
            List.of(key(familyId)),
            userId.toString(),
            deviceId,
            tokenHash,
            String.valueOf(ttl.toMillis()));
    if (!Long.valueOf(1L).equals(registered)) {
      throw new IllegalStateException("Refresh Token family already exists");
    }
  }

  @Override
  public RefreshTokenRotationResult rotate(
      String familyId,
      Long userId,
      String deviceId,
      String currentTokenHash,
      String newTokenHash,
      Duration ttl) {
    Long result =
        redisTemplate.execute(
            ROTATE_SCRIPT,
            List.of(key(familyId)),
            userId.toString(),
            deviceId,
            currentTokenHash,
            newTokenHash,
            String.valueOf(ttl.toMillis()));
    if (Long.valueOf(0L).equals(result)) {
      return RefreshTokenRotationResult.ROTATED;
    }
    if (Long.valueOf(1L).equals(result)) {
      return RefreshTokenRotationResult.INVALID;
    }
    if (Long.valueOf(2L).equals(result)) {
      return RefreshTokenRotationResult.DEVICE_MISMATCH;
    }
    if (Long.valueOf(3L).equals(result)) {
      return RefreshTokenRotationResult.REUSED;
    }
    throw new IllegalStateException("Unexpected Redis refresh rotation result");
  }

  @Override
  public boolean revoke(String familyId, Long userId, String deviceId, String tokenHash) {
    Long revoked =
        redisTemplate.execute(
            REVOKE_SCRIPT, List.of(key(familyId)), userId.toString(), deviceId, tokenHash);
    return Long.valueOf(1L).equals(revoked);
  }

  @Override
  public void revokeAll(Long userId) {
    redisTemplate.execute(REVOKE_ALL_SCRIPT, List.of(), KEY_PREFIX + "*", userId.toString());
  }

  private String key(String familyId) {
    return KEY_PREFIX + familyId;
  }
}
