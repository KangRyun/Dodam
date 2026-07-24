package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.dto.ConversationMessageSttStatusResponse;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.service.ConversationMessageSttStatusQueryService;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/** STT 상태 조회 Controller가 인증을 해석해 서비스에 위임하고 공통 응답으로 감싸는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class ConversationMessageDetailControllerTest {
  @Mock private GuardianUserResolver guardianResolver;
  @Mock private ConversationMessageSttStatusQueryService sttStatusQueryService;

  private ConversationMessageDetailController controller;

  @BeforeEach
  void setUp() {
    controller = new ConversationMessageDetailController(guardianResolver, sttStatusQueryService);
  }

  @Test
  void delegatesValidRequestAndReturnsOk() {
    ConversationMessageSttStatusResponse expected =
        new ConversationMessageSttStatusResponse(
            804L,
            803L,
            4,
            "CHILD",
            "ANSWER_VOICE",
            null,
            "친구랑 같이 있어서 좋아",
            "SUCCESS",
            new BigDecimal("0.9100"),
            false,
            LocalDateTime.parse("2026-07-21T02:36:12"));
    when(guardianResolver.resolve(null, "10")).thenReturn(10L);
    when(sttStatusQueryService.getSttStatus(10L, 804L)).thenReturn(expected);

    ResponseEntity<ApiResponse<ConversationMessageSttStatusResponse>> response =
        controller.getSttStatus(804L, null, "10");

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isNotNull();
    assertThat(response.getBody().data()).isSameAs(expected);
  }

  @Test
  void propagatesAccessDeniedFailure() {
    when(guardianResolver.resolve(null, "10")).thenReturn(10L);
    when(sttStatusQueryService.getSttStatus(10L, 804L))
        .thenThrow(
            new BusinessException(ConversationMessageStatusErrorCode.CONVERSATION_ACCESS_DENIED));

    assertThatThrownBy(() -> controller.getSttStatus(804L, null, "10"))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_ACCESS_DENIED);
  }

  @Test
  void resolvesGuardianBeforeQuery() {
    when(guardianResolver.resolve("Bearer token", null)).thenReturn(20L);
    when(sttStatusQueryService.getSttStatus(20L, 900L))
        .thenReturn(
            new ConversationMessageSttStatusResponse(
                900L,
                null,
                1,
                "AI",
                "QUESTION",
                "질문",
                null,
                "NOT_REQUIRED",
                null,
                false,
                LocalDateTime.parse("2026-07-21T02:30:00")));

    ResponseEntity<ApiResponse<ConversationMessageSttStatusResponse>> response =
        controller.getSttStatus(900L, "Bearer token", null);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody().data().speechStatus()).isEqualTo("NOT_REQUIRED");
  }

  @Test
  void doesNotQueryWhenAuthenticationFails() {
    when(guardianResolver.resolve(null, null))
        .thenThrow(
            new BusinessException(ConversationMessageStatusErrorCode.CONVERSATION_ACCESS_DENIED));

    assertThatThrownBy(() -> controller.getSttStatus(804L, null, null))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(sttStatusQueryService);
  }
}
