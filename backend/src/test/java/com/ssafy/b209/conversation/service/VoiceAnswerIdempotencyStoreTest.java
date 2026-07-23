package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.exception.VoiceAnswerErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/** 288번 음성 답변의 Redis 멱등 재생·재사용 충돌·장애 차단을 검증한다. */
@SuppressWarnings({"rawtypes", "unchecked"})
@ExtendWith(MockitoExtension.class)
class VoiceAnswerIdempotencyStoreTest {
  private static final long GUARDIAN_ID = 10L;
  private static final String URI = "/api/v1/conversations/20/answers/voice";
  private static final String KEY = "voice-request-key";
  private static final String FINGERPRINT = "a".repeat(64);

  @Mock private StringRedisTemplate redisTemplate;

  private VoiceAnswerIdempotencyStore store;

  @BeforeEach
  void setUp() {
    ConversationStartIdempotencyProperties properties =
        new ConversationStartIdempotencyProperties();
    properties.setProcessingWait(Duration.ZERO);
    store = new VoiceAnswerIdempotencyStore(redisTemplate, new ObjectMapper(), properties);
  }

  @Test
  void executesSupplierOnceForFirstClaimAndCompletesTheRedisRecord() {
    doAnswer(
            invocation -> {
              DefaultRedisScript<?> script = invocation.getArgument(0);
              return script.getResultType() == String.class ? "CLAIMED" : 1L;
            })
        .when(redisTemplate)
        .execute(any(DefaultRedisScript.class), anyList(), any(), any(), any());
    AtomicInteger supplierCalls = new AtomicInteger();

    ResponseEntity<?> response =
        store.execute(
            GUARDIAN_ID,
            URI,
            KEY,
            FINGERPRINT,
            () -> {
              supplierCalls.incrementAndGet();
              return ResponseEntity.status(HttpStatus.CREATED).body("created");
            });

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    assertThat(supplierCalls).hasValue(1);
  }

  @Test
  void replaysCompletedResponseWithoutExecutingSupplierAgain() throws Exception {
    ObjectMapper objectMapper = new ObjectMapper();
    String body = objectMapper.writeValueAsString(Map.of("messageId", 60));
    String completedRecord =
        objectMapper.writeValueAsString(
            Map.of(
                "fingerprint",
                FINGERPRINT,
                "state",
                "COMPLETED",
                "status",
                HttpStatus.CREATED.value(),
                "body",
                body));
    doAnswer(invocation -> "COMPLETED:" + completedRecord)
        .when(redisTemplate)
        .execute(any(DefaultRedisScript.class), anyList(), any(), any(), any());
    AtomicInteger supplierCalls = new AtomicInteger();

    ResponseEntity<?> response =
        store.execute(
            GUARDIAN_ID,
            URI,
            KEY,
            FINGERPRINT,
            () -> {
              supplierCalls.incrementAndGet();
              return ResponseEntity.status(HttpStatus.CREATED).build();
            });

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    assertThat(response.getBody()).hasToString(body);
    assertThat(supplierCalls).hasValue(0);
  }

  @Test
  void rejectsSameKeyWithDifferentFingerprint() {
    doAnswer(invocation -> "REUSED")
        .when(redisTemplate)
        .execute(any(DefaultRedisScript.class), anyList(), any(), any(), any());

    assertThatThrownBy(
            () ->
                store.execute(
                    GUARDIAN_ID,
                    URI,
                    KEY,
                    FINGERPRINT,
                    () -> ResponseEntity.status(HttpStatus.CREATED).build()))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED));
  }

  @Test
  void returnsConflictWhileSameFingerprintIsStillProcessing() {
    doAnswer(invocation -> "PROCESSING")
        .when(redisTemplate)
        .execute(any(DefaultRedisScript.class), anyList(), any(), any(), any());

    assertThatThrownBy(
            () ->
                store.execute(
                    GUARDIAN_ID,
                    URI,
                    KEY,
                    FINGERPRINT,
                    () -> ResponseEntity.status(HttpStatus.CREATED).build()))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(VoiceAnswerErrorCode.IDEMPOTENCY_IN_PROGRESS));
  }

  @Test
  void rejectsWhenRedisIsUnavailableInsteadOfFailingOpen() {
    doThrow(new DataAccessResourceFailureException("redis unavailable"))
        .when(redisTemplate)
        .execute(any(DefaultRedisScript.class), anyList(), any(), any(), any());

    assertThatThrownBy(
            () ->
                store.execute(
                    GUARDIAN_ID,
                    URI,
                    KEY,
                    FINGERPRINT,
                    () -> ResponseEntity.status(HttpStatus.CREATED).build()))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(VoiceAnswerErrorCode.IDEMPOTENCY_UNAVAILABLE));
  }
}
