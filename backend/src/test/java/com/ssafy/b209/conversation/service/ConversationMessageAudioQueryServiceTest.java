package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.exception.ConversationMessageAudioErrorCode;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.exception.SttProcessingErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.audio.OpenedAudio;
import com.ssafy.b209.storage.audio.StoredAudioReader;
import java.io.ByteArrayInputStream;
import java.lang.reflect.Constructor;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

/** 음성 답변 재생 서비스가 소유권을 검증하고 원본 존재 여부에 따라 재생 자원을 조립·거부하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class ConversationMessageAudioQueryServiceTest {
  private static final LocalDateTime CREATED_AT = LocalDateTime.of(2026, 7, 21, 2, 36, 12);
  private static final String STORAGE_KEY = "2026/07/24/2f0b8f5e-audio.webm";

  @Mock private ConversationHistoryMessageRepository messageRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private VoiceAnswerAuthorizationRepository authorizationRepository;
  @Mock private StoredAudioReader audioReader;

  private ConversationMessageAudioQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new ConversationMessageAudioQueryService(
            messageRepository,
            conversationSessionRepository,
            drawingSessionRepository,
            authorizationRepository,
            audioReader);
  }

  @Test
  void throwsNotFoundWhenMessageMissing() {
    when(messageRepository.findById(804L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.getPlayableAudio(10L, 804L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND);

    verifyNoInteractions(conversationSessionRepository, authorizationRepository, audioReader);
  }

  @Test
  void throwsAccessDeniedWhenGuardianNotRelated() {
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("VOICE_ANSWER", STORAGE_KEY)));
    when(conversationSessionRepository.findById(800L)).thenReturn(Optional.of(session()));
    when(drawingSessionRepository.findById(100L)).thenReturn(Optional.of(drawingSession(1L)));
    when(authorizationRepository.hasGuardianChildRelation(10L, 1L)).thenReturn(false);

    assertThatThrownBy(() -> service.getPlayableAudio(10L, 804L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_ACCESS_DENIED);

    verifyNoInteractions(audioReader);
  }

  @Test
  void throwsAudioNotAvailableWhenNotVoiceAnswer() {
    authorizeChild();
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("OPTION_ANSWER", STORAGE_KEY)));

    assertThatThrownBy(() -> service.getPlayableAudio(10L, 804L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageAudioErrorCode.CONVERSATION_AUDIO_NOT_AVAILABLE);

    verifyNoInteractions(audioReader);
  }

  @Test
  void throwsAudioNotAvailableWhenStorageKeyMissing() {
    authorizeChild();
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("VOICE_ANSWER", null)));

    assertThatThrownBy(() -> service.getPlayableAudio(10L, 804L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageAudioErrorCode.CONVERSATION_AUDIO_NOT_AVAILABLE);

    verifyNoInteractions(audioReader);
  }

  @Test
  void throwsAudioNotAvailableWhenOriginalDeletedOrMissing() {
    authorizeChild();
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("VOICE_ANSWER", STORAGE_KEY)));
    when(audioReader.open(STORAGE_KEY))
        .thenThrow(new BusinessException(SttProcessingErrorCode.STT_AUDIO_NOT_AVAILABLE));

    assertThatThrownBy(() -> service.getPlayableAudio(10L, 804L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageAudioErrorCode.CONVERSATION_AUDIO_NOT_AVAILABLE);
  }

  @Test
  void returnsPlayableResourceWithResolvedContentType() throws Exception {
    authorizeChild();
    byte[] audioBytes = "webm-bytes".getBytes(StandardCharsets.UTF_8);
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("VOICE_ANSWER", STORAGE_KEY)));
    when(audioReader.open(STORAGE_KEY))
        .thenReturn(new OpenedAudio(new ByteArrayInputStream(audioBytes), "voice.webm"));

    VoiceAnswerAudioResource resource = service.getPlayableAudio(10L, 804L);

    assertThat(resource.contentType()).isEqualTo("audio/webm");
    assertThat(resource.audio()).isNotNull();
    assertThat(resource.audio().inputStream().readAllBytes()).isEqualTo(audioBytes);
  }

  @Test
  void streamsQuestionTtsAudioWhenPresent() throws Exception {
    authorizeChild();
    byte[] audioBytes = "mp3-bytes".getBytes(StandardCharsets.UTF_8);
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("QUESTION", "2026/07/24/2f0b8f5e-tts.mp3")));
    when(audioReader.open("2026/07/24/2f0b8f5e-tts.mp3"))
        .thenReturn(new OpenedAudio(new ByteArrayInputStream(audioBytes), "audio.mp3"));

    VoiceAnswerAudioResource resource = service.getPlayableAudio(10L, 804L);

    assertThat(resource.contentType()).isEqualTo("audio/mpeg");
    assertThat(resource.audio().inputStream().readAllBytes()).isEqualTo(audioBytes);
  }

  private void authorizeChild() {
    when(conversationSessionRepository.findById(800L)).thenReturn(Optional.of(session()));
    when(drawingSessionRepository.findById(100L)).thenReturn(Optional.of(drawingSession(1L)));
    when(authorizationRepository.hasGuardianChildRelation(10L, 1L)).thenReturn(true);
  }

  private ConversationSession session() {
    return ConversationSession.start(100L, "LOWER_ELEMENTARY", 5, CREATED_AT);
  }

  private ConversationStartDrawingSession drawingSession(Long childId) {
    ConversationStartDrawingSession drawingSession =
        instantiate(ConversationStartDrawingSession.class);
    ReflectionTestUtils.setField(drawingSession, "id", 100L);
    ReflectionTestUtils.setField(drawingSession, "childId", childId);
    return drawingSession;
  }

  private ConversationHistoryMessage voiceMessage(String messageType, String audioStorageKey) {
    ConversationHistoryMessage message = instantiate(ConversationHistoryMessage.class);
    ReflectionTestUtils.setField(message, "id", 804L);
    ReflectionTestUtils.setField(message, "conversationSessionId", 800L);
    ReflectionTestUtils.setField(message, "messageSequence", 4);
    ReflectionTestUtils.setField(message, "senderType", "CHILD");
    ReflectionTestUtils.setField(message, "messageType", messageType);
    ReflectionTestUtils.setField(message, "audioStorageKey", audioStorageKey);
    ReflectionTestUtils.setField(message, "needsGuardianConfirmation", false);
    ReflectionTestUtils.setField(message, "skipped", false);
    ReflectionTestUtils.setField(message, "createdAt", CREATED_AT);
    return message;
  }

  private static <T> T instantiate(Class<T> type) {
    try {
      Constructor<T> constructor = type.getDeclaredConstructor();
      constructor.setAccessible(true);
      return constructor.newInstance();
    } catch (ReflectiveOperationException exception) {
      throw new IllegalStateException("Failed to instantiate " + type.getName(), exception);
    }
  }
}
