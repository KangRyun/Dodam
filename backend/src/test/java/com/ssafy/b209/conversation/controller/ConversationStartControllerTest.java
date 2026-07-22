package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.conversation.dto.StartConversationRequest;
import com.ssafy.b209.conversation.exception.ActiveConversationExistsException;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.service.ConversationStartIdempotencyStore;
import com.ssafy.b209.conversation.service.ConversationStartService;
import com.ssafy.b209.conversation.service.TemporaryGuardianResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import java.util.Map;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.invocation.InvocationOnMock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class ConversationStartControllerTest {
  @Mock private TemporaryGuardianResolver guardianResolver;
  @Mock private ConversationStartIdempotencyStore idempotencyStore;
  @Mock private ConversationStartService conversationStartService;

  private ConversationStartController controller;

  @BeforeEach
  void setUp() {
    controller =
        new ConversationStartController(
            guardianResolver, idempotencyStore, conversationStartService);
  }

  @Test
  @SuppressWarnings("unchecked")
  void returnsExistingConversationIdWithActiveConversationConflict() {
    StartConversationRequest request = new StartConversationRequest(700L, 5);
    given(guardianResolver.resolve("Bearer token", "9")).willReturn(9L);
    given(
            idempotencyStore.execute(
                eq(9L),
                eq("/api/v1/drawing-sessions/100/conversations"),
                eq("request-key-123"),
                eq(request),
                any(Supplier.class)))
        .willAnswer(this::executeFirstResponseSupplier);
    given(conversationStartService.start(9L, 100L, request))
        .willThrow(new ActiveConversationExistsException(800L));

    ResponseEntity<?> response =
        controller.start(100L, "Bearer token", "9", "request-key-123", request);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    assertThat(response.getBody()).isInstanceOf(ApiErrorResponse.class);
    ApiErrorResponse<?> body = (ApiErrorResponse<?>) response.getBody();
    assertThat(body.code())
        .isEqualTo(ConversationStartErrorCode.ACTIVE_CONVERSATION_EXISTS.getCode());
    assertThat(body.data()).isEqualTo(Map.of("conversationId", 800L));
  }

  @SuppressWarnings("unchecked")
  private ResponseEntity<?> executeFirstResponseSupplier(InvocationOnMock invocation) {
    Supplier<ResponseEntity<?>> supplier = (Supplier<ResponseEntity<?>>) invocation.getArgument(4);
    return supplier.get();
  }
}
