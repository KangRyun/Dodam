package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.dto.ConversationMessagePageResponse;
import com.ssafy.b209.conversation.service.ConversationMessageQueryService;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/** 대화 내역 조회 Controller가 페이지 조건을 검증하고 유효한 요청만 서비스에 위임하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class ConversationMessageListControllerTest {
  @Mock private GuardianUserResolver guardianResolver;
  @Mock private ConversationMessageQueryService messageQueryService;

  private ConversationMessageListController controller;

  @BeforeEach
  void setUp() {
    controller = new ConversationMessageListController(guardianResolver, messageQueryService);
  }

  @Test
  void rejectsNegativePageBeforeAuthenticationAndQuery() {
    assertThatThrownBy(() -> controller.getMessages(800L, -1, 50, null, null, null))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(guardianResolver, messageQueryService);
  }

  @Test
  void rejectsTooLargeSizeBeforeAuthenticationAndQuery() {
    assertThatThrownBy(() -> controller.getMessages(800L, 0, 101, null, null, null))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(guardianResolver, messageQueryService);
  }

  @Test
  void rejectsNegativeAfterSequenceBeforeAuthenticationAndQuery() {
    assertThatThrownBy(() -> controller.getMessages(800L, 0, 50, -1, null, null))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(guardianResolver, messageQueryService);
  }

  @Test
  void delegatesValidRequestAndReturnsOk() {
    ConversationMessagePageResponse page =
        new ConversationMessagePageResponse(List.of(), 0, 50, 0L, 0, true, true, false);
    when(guardianResolver.resolve(null, "10")).thenReturn(10L);
    when(messageQueryService.getMessages(eq(10L), eq(800L), eq(0), eq(50), any())).thenReturn(page);

    ResponseEntity<ApiResponse<ConversationMessagePageResponse>> response =
        controller.getMessages(800L, 0, 50, null, null, "10");

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isNotNull();
    assertThat(response.getBody().data()).isSameAs(page);
  }
}
