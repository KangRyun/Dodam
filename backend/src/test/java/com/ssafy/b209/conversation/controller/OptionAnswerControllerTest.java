package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.conversation.dto.OptionAnswerRequest;
import com.ssafy.b209.conversation.dto.SelectedOptionCommand;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.OptionAnswerService;
import com.ssafy.b209.conversation.service.VoiceAnswerIdempotencyStore;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** 선택형 답변 Controller가 인증·저장 전에 멱등성 Header를 검증하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class OptionAnswerControllerTest {
  @Mock private GuardianUserResolver guardianResolver;
  @Mock private OptionAnswerService optionAnswerService;
  @Mock private VoiceAnswerIdempotencyStore idempotencyStore;

  private OptionAnswerController controller;

  @BeforeEach
  void setUp() {
    controller =
        new OptionAnswerController(guardianResolver, optionAnswerService, idempotencyStore);
  }

  @Test
  void rejectsMissingIdempotencyKeyBeforeAuthenticationAndStorage() {
    OptionAnswerRequest request =
        new OptionAnswerRequest(
            803L, List.of(new SelectedOptionCommand("happy", "EMOTION", "HAPPY", "기뻐요")), null);

    assertThatThrownBy(() -> controller.submit(800L, null, null, null, request))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(guardianResolver, optionAnswerService, idempotencyStore);
  }

  @Test
  void rejectsTooShortIdempotencyKeyBeforeAuthenticationAndStorage() {
    OptionAnswerRequest request =
        new OptionAnswerRequest(
            803L, List.of(new SelectedOptionCommand("happy", "EMOTION", "HAPPY", "기뻐요")), null);

    assertThatThrownBy(() -> controller.submit(800L, null, null, "short", request))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(guardianResolver, optionAnswerService, idempotencyStore);
  }
}
