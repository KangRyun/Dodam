package com.ssafy.b209.infrastructure.ai.image;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.HexFormat;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.regex.Pattern;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;

/**
 * Redis TTL과 Lua Script를 이용해 일회성 이미지 조회 Token을 저장하고 소비한다.
 *
 * <p>Redis Key에는 원문 Token 대신 SHA-256 digest만 저장한다. 소비 시 조회와 삭제를 하나의 Lua Script로 수행하므로 동시 요청에서도 하나의
 * 요청만 Storage Key를 얻는다.
 */
public final class RedisAiImageAccessTokenStore implements AiImageAccessTokenStore {

  private static final String KEY_PREFIX = "ai:image-access:";
  private static final int MAX_ISSUE_ATTEMPTS = 3;
  private static final Pattern TOKEN_PATTERN = Pattern.compile("[A-Za-z0-9_-]{43}");
  private static final DefaultRedisScript<String> CONSUME_SCRIPT =
      new DefaultRedisScript<>(
          "local value = redis.call('GET', KEYS[1]) "
              + "if not value then return nil end "
              + "redis.call('DEL', KEYS[1]) return value",
          String.class);

  private final StringRedisTemplate redisTemplate;
  private final AiImageAccessTokenGenerator tokenGenerator;

  /**
   * Redis 기반 Token 저장소를 구성한다.
   *
   * @param redisTemplate TTL 저장과 Lua 실행에 사용할 Template
   * @param tokenGenerator 불투명 Token 생성기
   */
  public RedisAiImageAccessTokenStore(
      StringRedisTemplate redisTemplate, AiImageAccessTokenGenerator tokenGenerator) {
    this.redisTemplate = Objects.requireNonNull(redisTemplate, "redisTemplate must not be null");
    this.tokenGenerator = Objects.requireNonNull(tokenGenerator, "tokenGenerator must not be null");
  }

  @Override
  public String issue(String storageKey, Duration ttl) {
    if (storageKey == null || storageKey.isBlank()) {
      throw new IllegalArgumentException("storageKey must not be blank");
    }
    if (ttl == null || ttl.isZero() || ttl.isNegative()) {
      throw new IllegalArgumentException("ttl must be positive");
    }
    for (int attempt = 0; attempt < MAX_ISSUE_ATTEMPTS; attempt++) {
      String token = tokenGenerator.generate();
      if (!isValidToken(token)) {
        continue;
      }
      Boolean stored = redisTemplate.opsForValue().setIfAbsent(key(token), storageKey, ttl);
      if (Boolean.TRUE.equals(stored)) {
        return token;
      }
    }
    throw new IllegalStateException("Unable to allocate an AI image access token");
  }

  @Override
  public Optional<String> consume(String token) {
    if (!isValidToken(token)) {
      return Optional.empty();
    }
    return Optional.ofNullable(redisTemplate.execute(CONSUME_SCRIPT, List.of(key(token))));
  }

  private boolean isValidToken(String token) {
    return token != null && TOKEN_PATTERN.matcher(token).matches();
  }

  private String key(String token) {
    return KEY_PREFIX + sha256(token);
  }

  private String sha256(String value) {
    try {
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 algorithm is unavailable", exception);
    }
  }
}
