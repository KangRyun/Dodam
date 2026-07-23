package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.dto.StartConversationRequest;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import java.net.URI;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

class ConversationStartIdempotencyStoreTest {
  private static final long GUARDIAN_ID = 9L;
  private static final String API_URI = "/api/v1/drawing-sessions/100/conversations";
  private static final String KEY = "request-key-123";

  private InMemoryRedisOperations redisOperations;
  private ConversationStartIdempotencyProperties properties;
  private ConversationStartIdempotencyStore store;

  @BeforeEach
  void setUp() {
    redisOperations = new InMemoryRedisOperations();
    properties = new ConversationStartIdempotencyProperties();
    properties.setProcessingWait(Duration.ofSeconds(1));
    properties.setPollingInterval(Duration.ofMillis(10));
    store = new ConversationStartIdempotencyStore(redisOperations, new ObjectMapper(), properties);
  }

  @Test
  void replaysTheFirstResponseForConcurrentIdenticalRequests() throws Exception {
    CountDownLatch supplierEntered = new CountDownLatch(1);
    CountDownLatch allowCompletion = new CountDownLatch(1);
    AtomicInteger executions = new AtomicInteger();

    Thread first =
        new Thread(
            () ->
                store.execute(
                    GUARDIAN_ID,
                    API_URI,
                    KEY,
                    request(700L),
                    () -> {
                      executions.incrementAndGet();
                      supplierEntered.countDown();
                      await(allowCompletion);
                      return createdResponse();
                    }));
    first.start();
    assertThat(supplierEntered.await(1, TimeUnit.SECONDS)).isTrue();

    AtomicReference<ResponseEntity<?>> replayed = new AtomicReference<>();
    Thread second =
        new Thread(
            () ->
                replayed.set(
                    store.execute(
                        GUARDIAN_ID, API_URI, KEY, request(700L), this::createdResponse)));
    second.start();
    Thread.sleep(50);
    allowCompletion.countDown();
    first.join(1_000);
    second.join(1_000);

    assertThat(executions).hasValue(1);
    assertThat(replayed.get()).isNotNull();
    assertThat(replayed.get().getStatusCode()).isEqualTo(HttpStatus.CREATED);
    assertThat(replayed.get().getHeaders().getLocation())
        .isEqualTo(URI.create("/api/v1/conversations/800"));
    assertThat(replayed.get().getBody()).isInstanceOf(String.class);
  }

  @Test
  void replaysSameKeyAndSameBodyAfterApplicationRestart() {
    ResponseEntity<?> first =
        store.execute(GUARDIAN_ID, API_URI, KEY, request(700L), this::createdResponse);
    ConversationStartIdempotencyStore restartedStore =
        new ConversationStartIdempotencyStore(redisOperations, new ObjectMapper(), properties);

    ResponseEntity<?> replayed =
        restartedStore.execute(
            GUARDIAN_ID,
            API_URI,
            KEY,
            request(700L),
            () -> ResponseEntity.status(HttpStatus.CREATED).build());

    assertThat(first.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    assertThat(replayed.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    assertThat(replayed.getHeaders().getLocation())
        .isEqualTo(URI.create("/api/v1/conversations/800"));
  }

  @Test
  void rejectsSameKeyWithDifferentBody() {
    store.execute(GUARDIAN_ID, API_URI, KEY, request(700L), this::createdResponse);

    assertThatThrownBy(
            () -> store.execute(GUARDIAN_ID, API_URI, KEY, request(701L), this::createdResponse))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED));
  }

  @Test
  void returnsConflictWhenExistingRequestRemainsProcessing() {
    properties.setProcessingWait(Duration.ZERO);
    redisOperations.putProcessing(redisKey(), fingerprint(request(700L)));

    assertThatThrownBy(
            () -> store.execute(GUARDIAN_ID, API_URI, KEY, request(700L), this::createdResponse))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.CONVERSATION_START_CONFLICT));
  }

  @Test
  void processesNewRequestAfterTtlExpiration() {
    AtomicInteger executions = new AtomicInteger();
    store.execute(
        GUARDIAN_ID,
        API_URI,
        KEY,
        request(700L),
        () -> {
          executions.incrementAndGet();
          return createdResponse();
        });
    redisOperations.expire(redisKey());

    store.execute(
        GUARDIAN_ID,
        API_URI,
        KEY,
        request(700L),
        () -> {
          executions.incrementAndGet();
          return createdResponse();
        });

    assertThat(executions).hasValue(2);
  }

  @Test
  void storesSuccessConflictAndServerFailureResponses() {
    ResponseEntity<?> conflict =
        store.execute(
            GUARDIAN_ID,
            API_URI,
            KEY,
            request(700L),
            () ->
                ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(
                        ApiErrorResponse.of(
                            ConversationStartErrorCode.ACTIVE_CONVERSATION_EXISTS)));
    ResponseEntity<?> replayedConflict =
        store.execute(GUARDIAN_ID, API_URI, KEY, request(700L), this::createdResponse);

    assertThat(conflict.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    assertThat(replayedConflict.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);

    redisOperations.expire(redisKey());
    ResponseEntity<?> failure =
        store.execute(
            GUARDIAN_ID,
            API_URI,
            KEY,
            request(700L),
            () -> {
              throw new IllegalStateException("unexpected");
            });
    ResponseEntity<?> replayedFailure =
        store.execute(GUARDIAN_ID, API_URI, KEY, request(700L), this::createdResponse);

    assertThat(failure.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
    assertThat(replayedFailure.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
  }

  private StartConversationRequest request(Long analysisId) {
    return new StartConversationRequest(analysisId, 5);
  }

  private ResponseEntity<ApiResponse<Map<String, Long>>> createdResponse() {
    return ResponseEntity.created(URI.create("/api/v1/conversations/800"))
        .body(ApiResponse.of(CommonSuccessCode.CREATED, Map.of("conversationId", 800L)));
  }

  private String redisKey() {
    return "idempotency:" + GUARDIAN_ID + ":POST:" + API_URI + ':' + KEY;
  }

  private String fingerprint(StartConversationRequest request) {
    try {
      byte[] body = new ObjectMapper().writeValueAsBytes(request);
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(body));
    } catch (Exception exception) {
      throw new IllegalStateException(exception);
    }
  }

  private void await(CountDownLatch latch) {
    try {
      latch.await(1, TimeUnit.SECONDS);
    } catch (InterruptedException exception) {
      Thread.currentThread().interrupt();
      throw new IllegalStateException(exception);
    }
  }

  private static final class InMemoryRedisOperations
      implements ConversationIdempotencyRedisOperations {
    private final Map<String, Record> records = new HashMap<>();

    @Override
    public synchronized IdempotencyClaim claim(
        String redisKey, String fingerprint, Duration processingTtl) {
      Record record = records.get(redisKey);
      if (record == null) {
        records.put(redisKey, Record.processing(fingerprint));
        return IdempotencyClaim.claimed();
      }
      if (!record.fingerprint.equals(fingerprint)) {
        return IdempotencyClaim.reused();
      }
      return record.response == null
          ? IdempotencyClaim.processing()
          : IdempotencyClaim.completed(record.response);
    }

    @Override
    public synchronized boolean complete(
        String redisKey,
        String fingerprint,
        StoredConversationHttpResponse response,
        Duration responseTtl) {
      Record record = records.get(redisKey);
      if (record == null || record.response != null || !record.fingerprint.equals(fingerprint)) {
        return false;
      }
      records.put(redisKey, new Record(fingerprint, response));
      return true;
    }

    synchronized void putProcessing(String redisKey, String fingerprint) {
      records.put(redisKey, Record.processing(fingerprint));
    }

    synchronized void expire(String redisKey) {
      records.remove(redisKey);
    }

    private static final class Record {
      private final String fingerprint;
      private final StoredConversationHttpResponse response;

      private Record(String fingerprint, StoredConversationHttpResponse response) {
        this.fingerprint = fingerprint;
        this.response = response;
      }

      private static Record processing(String fingerprint) {
        return new Record(fingerprint, null);
      }
    }
  }
}
