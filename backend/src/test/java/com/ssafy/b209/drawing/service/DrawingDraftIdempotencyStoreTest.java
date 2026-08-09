package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.dto.request.SaveDrawingDraftRequest;
import com.ssafy.b209.drawing.dto.response.DrawingCanvasStateResponse;
import com.ssafy.b209.drawing.dto.response.DrawingDraftResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataAccessResourceFailureException;

@ExtendWith(MockitoExtension.class)
class DrawingDraftIdempotencyStoreTest {

  @Mock private DrawingDraftIdempotencyRedisOperations redisOperations;

  private DrawingDraftIdempotencyStore store;
  private ObjectMapper objectMapper;

  @BeforeEach
  void setUp() {
    objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());
    store =
        new DrawingDraftIdempotencyStore(
            redisOperations, new DrawingDraftIdempotencyProperties(), objectMapper);
  }

  @Test
  void storesTheFirstSuccessAndReturnsIt() {
    given(redisOperations.claim(any(), any(), any()))
        .willReturn(DrawingDraftIdempotencyClaim.claimed());
    AtomicInteger executions = new AtomicInteger();

    DrawingDraftResponse result =
        store.execute(
            1L,
            10L,
            "draft-key-0001",
            new byte[] {1, 2, 3},
            request(17),
            () -> {
              executions.incrementAndGet();
              return response();
            });

    assertThat(result).isEqualTo(response());
    assertThat(executions).hasValue(1);
    verify(redisOperations).complete(any(), any(), any(), any());
  }

  @Test
  void replaysCompletedResponseWithoutSavingAgain() throws Exception {
    given(redisOperations.claim(any(), any(), any()))
        .willReturn(
            DrawingDraftIdempotencyClaim.completed(objectMapper.writeValueAsString(response())));

    DrawingDraftResponse result =
        store.execute(
            1L,
            10L,
            "draft-key-0001",
            new byte[] {1, 2, 3},
            request(17),
            () -> {
              throw new AssertionError("must not save");
            });

    assertThat(result).isEqualTo(response());
    verify(redisOperations, never()).complete(any(), any(), any(), any());
  }

  @Test
  void rejectsTheSameKeyWithAnotherMultipartFingerprint() {
    given(redisOperations.claim(any(), any(), any()))
        .willReturn(DrawingDraftIdempotencyClaim.reused());

    assertThatThrownBy(
            () ->
                store.execute(
                    1L, 10L, "draft-key-0001", new byte[] {9, 9, 9}, request(18), this::response))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(DrawingErrorCode.DRAFT_IDEMPOTENCY_KEY_REUSED));
  }

  @Test
  void releasesTheClaimWhenStorageFails() {
    given(redisOperations.claim(any(), any(), any()))
        .willReturn(DrawingDraftIdempotencyClaim.claimed());

    assertThatThrownBy(
            () ->
                store.execute(
                    1L,
                    10L,
                    "draft-key-0001",
                    new byte[] {1},
                    request(17),
                    () -> {
                      throw new IllegalStateException("storage failed");
                    }))
        .isInstanceOf(IllegalStateException.class);

    verify(redisOperations).release(any(), any());
  }

  @Test
  void doesNotSaveAgainWhenRedisCompletionFailsAfterStorageSuccess() {
    given(redisOperations.claim(any(), any(), any()))
        .willReturn(DrawingDraftIdempotencyClaim.claimed());
    given(redisOperations.complete(any(), any(), any(), any()))
        .willThrow(new DataAccessResourceFailureException("redis unavailable"));
    AtomicInteger executions = new AtomicInteger();

    DrawingDraftResponse result =
        store.execute(
            1L,
            10L,
            "draft-key-0001",
            new byte[] {1, 2, 3},
            request(17),
            () -> {
              executions.incrementAndGet();
              return response();
            });

    assertThat(result).isEqualTo(response());
    assertThat(executions).hasValue(1);
    verify(redisOperations, never()).release(any(), any());
  }

  @Test
  void concurrentSameRequestsShareTheFirstCompletedResponse() throws Exception {
    ConcurrentFakeRedisOperations fake = new ConcurrentFakeRedisOperations();
    DrawingDraftIdempotencyProperties properties = new DrawingDraftIdempotencyProperties();
    properties.setProcessingWait(Duration.ofSeconds(1));
    properties.setPollingInterval(Duration.ofMillis(5));
    DrawingDraftIdempotencyStore concurrentStore =
        new DrawingDraftIdempotencyStore(fake, properties, objectMapper);
    CountDownLatch firstStarted = new CountDownLatch(1);
    CountDownLatch finishFirst = new CountDownLatch(1);
    AtomicInteger saves = new AtomicInteger();

    CompletableFuture<DrawingDraftResponse> first =
        CompletableFuture.supplyAsync(
            () ->
                concurrentStore.execute(
                    1L,
                    10L,
                    "draft-key-0001",
                    new byte[] {1, 2, 3},
                    request(17),
                    () -> {
                      saves.incrementAndGet();
                      firstStarted.countDown();
                      await(finishFirst);
                      return response();
                    }));
    assertThat(firstStarted.await(1, TimeUnit.SECONDS)).isTrue();
    CompletableFuture<DrawingDraftResponse> second =
        CompletableFuture.supplyAsync(
            () ->
                concurrentStore.execute(
                    1L,
                    10L,
                    "draft-key-0001",
                    new byte[] {1, 2, 3},
                    request(17),
                    () -> {
                      saves.incrementAndGet();
                      return response();
                    }));
    Thread.sleep(20);
    finishFirst.countDown();

    assertThat(first.get(1, TimeUnit.SECONDS)).isEqualTo(response());
    assertThat(second.get(1, TimeUnit.SECONDS)).isEqualTo(response());
    assertThat(saves).hasValue(1);
  }

  private SaveDrawingDraftRequest request(long sequence) {
    return new SaveDrawingDraftRequest(sequence, OffsetDateTime.parse("2026-07-31T10:00:00+09:00"));
  }

  private DrawingDraftResponse response() {
    return new DrawingDraftResponse(
        20L,
        10L,
        DrawingAssetType.DRAFT,
        3,
        17,
        false,
        "image/png",
        3,
        100,
        100,
        Instant.parse("2026-07-31T01:00:00Z"),
        Instant.parse("2026-07-31T01:00:01Z"),
        null,
        "/api/v1/drawing-assets/20/file",
        new DrawingCanvasStateResponse(17, Instant.parse("2026-07-31T01:00:00Z")));
  }

  private void await(CountDownLatch latch) {
    try {
      latch.await();
    } catch (InterruptedException exception) {
      Thread.currentThread().interrupt();
      throw new IllegalStateException(exception);
    }
  }

  private static final class ConcurrentFakeRedisOperations
      implements DrawingDraftIdempotencyRedisOperations {

    private String fingerprint;
    private String responseJson;
    private boolean processing;

    @Override
    public synchronized DrawingDraftIdempotencyClaim claim(
        String redisKey, String requestedFingerprint, Duration processingTtl) {
      if (fingerprint == null) {
        fingerprint = requestedFingerprint;
        processing = true;
        return DrawingDraftIdempotencyClaim.claimed();
      }
      if (!fingerprint.equals(requestedFingerprint)) {
        return DrawingDraftIdempotencyClaim.reused();
      }
      if (responseJson != null) {
        return DrawingDraftIdempotencyClaim.completed(responseJson);
      }
      return DrawingDraftIdempotencyClaim.processing();
    }

    @Override
    public synchronized boolean complete(
        String redisKey,
        String requestedFingerprint,
        String storedResponseJson,
        Duration completedTtl) {
      if (!processing || !fingerprint.equals(requestedFingerprint)) {
        return false;
      }
      responseJson = storedResponseJson;
      processing = false;
      return true;
    }

    @Override
    public synchronized void release(String redisKey, String requestedFingerprint) {
      fingerprint = null;
      responseJson = null;
      processing = false;
    }
  }
}
