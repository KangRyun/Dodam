package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.dto.NextQuestionRequest;
import com.ssafy.b209.conversation.dto.PreferredResponseMode;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.CommonErrorCode;
import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class ConversationQuestionIdempotencyStoreTest {
  private static final long GUARDIAN_ID = 9L;
  private static final String URI = "/api/v1/conversations/11/next-question";
  private static final String KEY = "request-key-123";

  @Mock private ConversationIdempotencyRedisOperations redisOperations;

  private ConversationStartIdempotencyProperties properties;
  private ConversationQuestionIdempotencyStore store;

  @BeforeEach
  void setUp() {
    properties = new ConversationStartIdempotencyProperties();
    properties.setProcessingWait(Duration.ZERO);
    store =
        new ConversationQuestionIdempotencyStore(redisOperations, new ObjectMapper(), properties);
  }

  @Test
  void rejectsMissingIdempotencyKeyAsCommonBadRequest() {
    assertThatThrownBy(() -> store.execute(GUARDIAN_ID, URI, " ", request(700L), this::ok))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommonErrorCode.INVALID_INPUT_VALUE));
  }

  @Test
  void rejectsSameKeyWithDifferentBodyAsIdempotencyKeyReused() {
    given(redisOperations.claim(any(), any(), any())).willReturn(IdempotencyClaim.reused());

    assertThatThrownBy(() -> store.execute(GUARDIAN_ID, URI, KEY, request(701L), this::ok))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.IDEMPOTENCY_KEY_REUSED));
  }

  @Test
  void rejectsUnfinishedProcessingRequestWithQuestionStorageConflict() {
    given(redisOperations.claim(any(), any(), any())).willReturn(IdempotencyClaim.processing());

    assertThatThrownBy(() -> store.execute(GUARDIAN_ID, URI, KEY, request(700L), this::ok))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationErrorCode.QUESTION_STORAGE_CONFLICT));
  }

  @Test
  void replaysCompletedResponseForSameKeyAndBody() {
    given(redisOperations.claim(any(), any(), any()))
        .willReturn(
            IdempotencyClaim.completed(
                new StoredConversationHttpResponse(200, null, "{\"ok\":true}")));

    ResponseEntity<?> response = store.execute(GUARDIAN_ID, URI, KEY, request(700L), this::ok);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isEqualTo("{\"ok\":true}");
  }

  private NextQuestionRequest request(Long basisAnalysisId) {
    return new NextQuestionRequest(basisAnalysisId, null, List.of(PreferredResponseMode.VOICE));
  }

  private ResponseEntity<?> ok() {
    return ResponseEntity.ok().build();
  }
}
