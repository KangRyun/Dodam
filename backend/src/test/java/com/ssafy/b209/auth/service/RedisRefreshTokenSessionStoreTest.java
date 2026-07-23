package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;

@ExtendWith(MockitoExtension.class)
class RedisRefreshTokenSessionStoreTest {

  @Mock private StringRedisTemplate redisTemplate;

  @Test
  @SuppressWarnings("unchecked")
  void mapsHashMismatchToReuseDetection() {
    when(redisTemplate.execute(
            any(RedisScript.class), anyList(), any(), any(), any(), any(), any()))
        .thenReturn(3L);
    RedisRefreshTokenSessionStore store = new RedisRefreshTokenSessionStore(redisTemplate);

    RefreshTokenRotationResult result =
        store.rotate("family-1", 41L, "device-1", "old-hash", "new-hash", Duration.ofDays(14));

    assertThat(result).isEqualTo(RefreshTokenRotationResult.REUSED);
  }

  @Test
  @SuppressWarnings("unchecked")
  void reportsWhetherExactRefreshSessionWasRevoked() {
    when(redisTemplate.execute(any(RedisScript.class), anyList(), any(), any(), any()))
        .thenReturn(1L, 0L);
    RedisRefreshTokenSessionStore store = new RedisRefreshTokenSessionStore(redisTemplate);

    assertThat(store.revoke("family-1", 41L, "device-1", "token-hash")).isTrue();
    assertThat(store.revoke("family-1", 41L, "device-1", "token-hash")).isFalse();
    verify(redisTemplate, times(2))
        .execute(
            any(RedisScript.class),
            eq(List.of("auth:refresh:family:family-1")),
            eq("41"),
            eq("device-1"),
            eq("token-hash"));
  }
}
