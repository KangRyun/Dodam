package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.conversation.dto.NextQuestionRequest;
import com.ssafy.b209.conversation.dto.PreferredResponseMode;
import com.ssafy.b209.conversation.service.ConversationNextQuestionService;
import com.ssafy.b209.conversation.service.ConversationQuestionIdempotencyStore;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.CommonErrorCode;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ConversationNextQuestionControllerTest {
  @Mock private GuardianUserResolver guardianResolver;
  @Mock private ConversationQuestionIdempotencyStore idempotencyStore;
  @Mock private ConversationNextQuestionService nextQuestionService;

  private ConversationNextQuestionController controller;

  @BeforeEach
  void setUp() {
    controller =
        new ConversationNextQuestionController(
            guardianResolver, idempotencyStore, nextQuestionService);
  }

  @Test
  void rejectsMissingIdempotencyKeyAsCommonBadRequestBeforeAuthenticationOrRedis() {
    assertThatThrownBy(() -> controller.nextQuestion(11L, null, null, null, request()))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                org.assertj.core.api.Assertions.assertThat(exception.getErrorCode())
                    .isEqualTo(CommonErrorCode.INVALID_INPUT_VALUE));

    verifyNoInteractions(guardianResolver, idempotencyStore, nextQuestionService);
  }

  private NextQuestionRequest request() {
    return new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.VOICE));
  }
}
