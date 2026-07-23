package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.VoiceAnswerIdempotencyStore;
import com.ssafy.b209.conversation.service.VoiceAnswerService;
import com.ssafy.b209.global.exception.BusinessException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** 음성 답변 Controller가 인증·파일 처리 전에 멱등성 Header를 검증하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class VoiceAnswerControllerTest {
  @Mock private GuardianUserResolver guardianResolver;
  @Mock private VoiceAnswerService voiceAnswerService;
  @Mock private VoiceAnswerIdempotencyStore idempotencyStore;

  private VoiceAnswerController controller;

  @BeforeEach
  void setUp() {
    controller =
        new VoiceAnswerController(
            guardianResolver, voiceAnswerService, idempotencyStore, new ObjectMapper());
  }

  @Test
  void rejectsMissingIdempotencyKeyBeforeAuthenticationAndFileStorage() {
    assertThatThrownBy(() -> controller.upload(11L, null, null, null, null, null))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(guardianResolver, voiceAnswerService, idempotencyStore);
  }
}
