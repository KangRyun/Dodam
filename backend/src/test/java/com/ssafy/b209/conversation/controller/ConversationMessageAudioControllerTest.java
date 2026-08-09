package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.conversation.exception.ConversationMessageAudioErrorCode;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.service.ConversationMessageAudioQueryService;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.VoiceAnswerAudioResource;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.audio.OpenedAudio;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/** 음성 답변 재생 Controller가 인증을 해석해 서비스에 위임하고 캐시 금지 Header와 함께 원본을 스트리밍하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class ConversationMessageAudioControllerTest {
  @Mock private GuardianUserResolver guardianResolver;
  @Mock private ConversationMessageAudioQueryService audioQueryService;

  private ConversationMessageAudioController controller;

  @BeforeEach
  void setUp() {
    controller = new ConversationMessageAudioController(guardianResolver, audioQueryService);
  }

  @Test
  void streamsAudioWithPrivateNoStoreHeaders() throws Exception {
    byte[] audioBytes = "webm-bytes".getBytes(StandardCharsets.UTF_8);
    AtomicBoolean closed = new AtomicBoolean(false);
    OpenedAudio audio =
        new OpenedAudio(
            new ByteArrayInputStream(audioBytes) {
              @Override
              public void close() {
                closed.set(true);
              }
            },
            "voice.webm");
    when(guardianResolver.resolve("Bearer token", null)).thenReturn(10L);
    when(audioQueryService.getPlayableAudio(10L, 804L))
        .thenReturn(new VoiceAnswerAudioResource("audio/webm", audio));

    ResponseEntity<StreamingResponseBody> response =
        controller.getVoiceAnswerAudio(804L, "Bearer token", null);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getHeaders().getContentType()).isNotNull();
    assertThat(response.getHeaders().getContentType().toString()).isEqualTo("audio/webm");
    String cacheControl = response.getHeaders().getCacheControl();
    assertThat(cacheControl).contains("no-store").contains("private");

    ByteArrayOutputStream sink = new ByteArrayOutputStream();
    response.getBody().writeTo(sink);
    assertThat(sink.toByteArray()).isEqualTo(audioBytes);
    assertThat(closed).isTrue();
  }

  @Test
  void propagatesNotFoundFailure() {
    when(guardianResolver.resolve(null, "10")).thenReturn(10L);
    when(audioQueryService.getPlayableAudio(10L, 804L))
        .thenThrow(
            new BusinessException(
                ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND));

    assertThatThrownBy(() -> controller.getVoiceAnswerAudio(804L, null, "10"))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND);
  }

  @Test
  void propagatesAudioNotAvailableFailure() {
    when(guardianResolver.resolve(null, "10")).thenReturn(10L);
    when(audioQueryService.getPlayableAudio(10L, 804L))
        .thenThrow(
            new BusinessException(
                ConversationMessageAudioErrorCode.CONVERSATION_AUDIO_NOT_AVAILABLE));

    assertThatThrownBy(() -> controller.getVoiceAnswerAudio(804L, null, "10"))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageAudioErrorCode.CONVERSATION_AUDIO_NOT_AVAILABLE);
  }

  @Test
  void doesNotQueryWhenAuthenticationFails() {
    when(guardianResolver.resolve(null, null))
        .thenThrow(new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED));

    assertThatThrownBy(() -> controller.getVoiceAnswerAudio(804L, null, null))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(AuthErrorCode.AUTHENTICATION_REQUIRED);

    verifyNoInteractions(audioQueryService);
  }
}
