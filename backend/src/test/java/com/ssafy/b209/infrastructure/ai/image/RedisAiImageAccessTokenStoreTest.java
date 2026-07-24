package com.ssafy.b209.infrastructure.ai.image;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.HexFormat;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.data.redis.core.script.RedisScript;

@ExtendWith(MockitoExtension.class)
class RedisAiImageAccessTokenStoreTest {

  private static final String TOKEN = "abcdefghijklmnopqrstuvwxyzABCDEFGH012345678";

  @Mock private StringRedisTemplate redisTemplate;
  @Mock private ValueOperations<String, String> valueOperations;
  @Mock private AiImageAccessTokenGenerator tokenGenerator;

  @Test
  void issuesAnOpaqueTokenAndStoresOnlyItsDigestWithTtl() {
    when(redisTemplate.opsForValue()).thenReturn(valueOperations);
    when(tokenGenerator.generate()).thenReturn(TOKEN);
    when(valueOperations.setIfAbsent(any(), eq("2026/07/image.png"), eq(Duration.ofSeconds(60))))
        .thenReturn(true);
    RedisAiImageAccessTokenStore store =
        new RedisAiImageAccessTokenStore(redisTemplate, tokenGenerator);

    String issued = store.issue("2026/07/image.png", Duration.ofSeconds(60));

    assertThat(issued).isEqualTo(TOKEN);
    verify(valueOperations)
        .setIfAbsent(
            "ai:image-access:" + sha256(TOKEN), "2026/07/image.png", Duration.ofSeconds(60));
  }

  @Test
  @SuppressWarnings("unchecked")
  void consumesTheStorageKeyAtomicallyOnlyOnce() {
    when(redisTemplate.execute(any(RedisScript.class), anyList()))
        .thenReturn("image.png")
        .thenReturn(null);
    RedisAiImageAccessTokenStore store =
        new RedisAiImageAccessTokenStore(redisTemplate, tokenGenerator);

    assertThat(store.consume(TOKEN)).contains("image.png");
    assertThat(store.consume(TOKEN)).isEmpty();
    verify(redisTemplate, times(2))
        .execute(any(RedisScript.class), eq(java.util.List.of("ai:image-access:" + sha256(TOKEN))));
  }

  @Test
  void rejectsMalformedTokensWithoutQueryingRedis() {
    RedisAiImageAccessTokenStore store =
        new RedisAiImageAccessTokenStore(redisTemplate, tokenGenerator);

    Optional<String> consumed = store.consume("../invalid");

    assertThat(consumed).isEmpty();
    verify(redisTemplate, never()).execute(any(RedisScript.class), anyList());
  }

  @Test
  void stopsAfterRepeatedTokenCollisions() {
    when(redisTemplate.opsForValue()).thenReturn(valueOperations);
    when(tokenGenerator.generate()).thenReturn(TOKEN);
    when(valueOperations.setIfAbsent(any(), any(), any())).thenReturn(false);
    RedisAiImageAccessTokenStore store =
        new RedisAiImageAccessTokenStore(redisTemplate, tokenGenerator);

    assertThatThrownBy(() -> store.issue("image.png", Duration.ofSeconds(60)))
        .isInstanceOf(IllegalStateException.class);
  }

  private static String sha256(String value) {
    try {
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException exception) {
      throw new AssertionError(exception);
    }
  }
}
