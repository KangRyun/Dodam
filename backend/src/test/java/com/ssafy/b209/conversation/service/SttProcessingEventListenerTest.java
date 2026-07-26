package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.conversation.exception.SttProcessingErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** 업로드 커밋 후 STT 트리거가 실제로 호출되는지와 실패가 흡수되는지 검증한다. */
@ExtendWith(MockitoExtension.class)
class SttProcessingEventListenerTest {
  private static final long MESSAGE_ID = 60L;

  @Mock private SttProcessingService sttProcessingService;

  @InjectMocks private SttProcessingEventListener listener;

  @Test
  void processesStoredVoiceAnswer() {
    listener.onVoiceAnswerStored(new VoiceAnswerStoredEvent(MESSAGE_ID));

    verify(sttProcessingService).process(MESSAGE_ID);
  }

  @Test
  void absorbsProcessingFailureSoUploadResponseIsNotAffected() {
    willThrow(new BusinessException(SttProcessingErrorCode.CONVERSATION_NOT_CONVERSING))
        .given(sttProcessingService)
        .process(MESSAGE_ID);

    assertThatCode(() -> listener.onVoiceAnswerStored(new VoiceAnswerStoredEvent(MESSAGE_ID)))
        .doesNotThrowAnyException();
  }
}
