package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import com.ssafy.b209.conversation.dto.EndConversationRequest;
import com.ssafy.b209.conversation.dto.EndConversationResponse;
import com.ssafy.b209.conversation.exception.ConversationEndErrorCode;
import com.ssafy.b209.conversation.service.ConversationEndService;
import com.ssafy.b209.conversation.service.ConversationQuestionIdempotencyStore;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import java.time.LocalDateTime;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class ConversationEndControllerTest {

  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private ConversationQuestionIdempotencyStore idempotencyStore;
  @Mock private ConversationEndService conversationEndService;

  private ConversationEndController controller;

  @BeforeEach
  void setUp() {
    controller =
        new ConversationEndController(
            currentUserResolver, idempotencyStore, conversationEndService);
  }

  @Test
  void rejectsInvalidIdempotencyKeyBeforeAuthenticationOrServiceCall() {
    assertThatThrownBy(() -> controller.end(20L, "short", request()))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommonErrorCode.INVALID_INPUT_VALUE));

    verifyNoInteractions(currentUserResolver, idempotencyStore, conversationEndService);
  }

  @Test
  void returnsStoredEndResultThroughIdempotencyBoundary() {
    LocalDateTime completedAt = LocalDateTime.of(2026, 7, 25, 10, 30);
    EndConversationResponse result =
        new EndConversationResponse(
            20L,
            "COMPLETED",
            true,
            ConversationCompletionReason.GUARDIAN_REQUEST,
            completedAt,
            DrawingStage.REFLECTION);
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(conversationEndService.end(20L, request())).willReturn(result);
    given(
            idempotencyStore.execute(
                eq(7L),
                eq("/api/v1/conversations/20/end"),
                eq("conversation-end-key"),
                eq(request()),
                any(),
                eq(ConversationEndErrorCode.CONVERSATION_END_CONFLICT)))
        .willAnswer(
            invocation -> {
              Supplier<ResponseEntity<?>> supplier = invocation.getArgument(4);
              return supplier.get();
            });

    ResponseEntity<?> response = controller.end(20L, "conversation-end-key", request());

    assertThat(response.getStatusCode().value()).isEqualTo(200);
    assertThat(response.getBody()).isInstanceOfSatisfying(ApiResponse.class, body -> {});
    verify(conversationEndService).end(20L, request());
  }

  private EndConversationRequest request() {
    return new EndConversationRequest(ConversationCompletionReason.GUARDIAN_REQUEST, 803L);
  }
}
