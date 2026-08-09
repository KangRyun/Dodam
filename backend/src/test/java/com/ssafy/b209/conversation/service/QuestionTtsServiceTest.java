package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.TtsGenerateRequest;
import com.ssafy.b209.conversation.dto.TtsGenerateResponse;
import com.ssafy.b209.conversation.dto.TtsToneProfile;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.exception.QuestionTtsErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.tts.AiTtsClient;
import com.ssafy.b209.infrastructure.ai.tts.AiTtsClientException;
import com.ssafy.b209.infrastructure.ai.tts.TtsSynthesis;
import com.ssafy.b209.infrastructure.ai.tts.TtsSynthesisCommand;
import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.StagedAudio;
import com.ssafy.b209.storage.audio.StoredAudio;
import java.lang.reflect.Constructor;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

/** 질문 TTS 오케스트레이터가 소유권·타입 검증, 캐시 히트, 합성 저장, 실패·경합 처리를 올바르게 수행하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class QuestionTtsServiceTest {
  private static final LocalDateTime CREATED_AT = LocalDateTime.of(2026, 7, 21, 2, 36, 12);
  private static final Long GUARDIAN_ID = 10L;
  private static final Long MESSAGE_ID = 803L;
  private static final Long SESSION_ID = 800L;
  private static final Long DRAWING_SESSION_ID = 100L;
  private static final Long CHILD_ID = 1L;
  private static final BigDecimal SPEED = new BigDecimal("0.95");
  private static final TtsToneProfile TONE_PROFILE = TtsToneProfile.CHARACTER_DEFAULT_V1;
  private static final String SUBTITLE = "이 그림에서 무엇이 보이니?";
  private static final String STORAGE_KEY = "2026/07/24/2f0b8f5e-tts.mp3";
  private static final String AUDIO_URL = "/api/v1/conversation-messages/803/audio";

  @Mock private ConversationHistoryMessageRepository messageRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private VoiceAnswerAuthorizationRepository authorizationRepository;
  @Mock private QuestionTtsPersistenceService persistenceService;
  @Mock private AiTtsClient aiTtsClient;
  @Mock private AudioStorage audioStorage;

  private QuestionTtsService service;

  @BeforeEach
  void setUp() {
    service =
        new QuestionTtsService(
            messageRepository,
            conversationSessionRepository,
            drawingSessionRepository,
            authorizationRepository,
            persistenceService,
            aiTtsClient,
            audioStorage);
  }

  @Test
  void returnsCachedMetadataWithoutCallingAi() {
    authorizeQuestion();
    when(persistenceService.claim(MESSAGE_ID, "CHILD_FRIENDLY_01", SPEED, TONE_PROFILE))
        .thenReturn(
            new QuestionTtsClaimResult(
                QuestionTtsClaimResult.Action.CACHE_HIT, MESSAGE_ID, SUBTITLE, STORAGE_KEY));

    TtsGenerateResponse response = service.generate(GUARDIAN_ID, MESSAGE_ID, request());

    assertThat(response.audioUrl()).isEqualTo(AUDIO_URL);
    assertThat(response.expiresAt()).isNull();
    assertThat(response.durationMs()).isNull();
    assertThat(response.subtitle()).isEqualTo(SUBTITLE);
    verifyNoInteractions(aiTtsClient, audioStorage);
  }

  @Test
  void synthesizesStoresAndReturnsMetadataOnCacheMiss() {
    authorizeQuestion();
    when(persistenceService.claim(MESSAGE_ID, "CHILD_FRIENDLY_01", SPEED, TONE_PROFILE))
        .thenReturn(
            new QuestionTtsClaimResult(
                QuestionTtsClaimResult.Action.CLAIMED, MESSAGE_ID, SUBTITLE, null));
    when(aiTtsClient.synthesize(any(TtsSynthesisCommand.class)))
        .thenReturn(new TtsSynthesis(new byte[] {1, 2, 3}, "mp3"));
    StagedAudio staged = org.mockito.Mockito.mock(StagedAudio.class);
    when(audioStorage.stage(any())).thenReturn(staged);
    when(audioStorage.promote(staged))
        .thenReturn(new StoredAudio(STORAGE_KEY, "audio/mpeg", 3L, "checksum", 1040L));
    when(persistenceService.completeSuccess(
            MESSAGE_ID, STORAGE_KEY, AUDIO_URL, "CHILD_FRIENDLY_01", SPEED, TONE_PROFILE))
        .thenReturn(true);

    TtsGenerateResponse response = service.generate(GUARDIAN_ID, MESSAGE_ID, request());

    assertThat(response.audioUrl()).isEqualTo(AUDIO_URL);
    assertThat(response.durationMs()).isEqualTo(1040L);
    assertThat(response.subtitle()).isEqualTo(SUBTITLE);
    verify(audioStorage, never()).delete(any());
    ArgumentCaptor<TtsSynthesisCommand> commandCaptor =
        ArgumentCaptor.forClass(TtsSynthesisCommand.class);
    verify(aiTtsClient).synthesize(commandCaptor.capture());
    assertThat(commandCaptor.getValue().toneProfile()).isEqualTo(TONE_PROFILE);
  }

  @Test
  void marksFailedAndReportsTtsFailedWhenAiThrows() {
    authorizeQuestion();
    when(persistenceService.claim(MESSAGE_ID, "CHILD_FRIENDLY_01", SPEED, TONE_PROFILE))
        .thenReturn(
            new QuestionTtsClaimResult(
                QuestionTtsClaimResult.Action.CLAIMED, MESSAGE_ID, SUBTITLE, null));
    when(aiTtsClient.synthesize(any(TtsSynthesisCommand.class)))
        .thenThrow(new AiTtsClientException(AiTtsClientException.Type.SERVER_ERROR));

    assertThatThrownBy(() -> service.generate(GUARDIAN_ID, MESSAGE_ID, request()))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(QuestionTtsErrorCode.TTS_FAILED);

    verify(persistenceService).markFailed(MESSAGE_ID, "CHILD_FRIENDLY_01", SPEED, TONE_PROFILE);
  }

  @Test
  void deletesStoredFileAndReportsConflictWhenCompleteLosesRace() {
    authorizeQuestion();
    when(persistenceService.claim(MESSAGE_ID, "CHILD_FRIENDLY_01", SPEED, TONE_PROFILE))
        .thenReturn(
            new QuestionTtsClaimResult(
                QuestionTtsClaimResult.Action.CLAIMED, MESSAGE_ID, SUBTITLE, null));
    when(aiTtsClient.synthesize(any(TtsSynthesisCommand.class)))
        .thenReturn(new TtsSynthesis(new byte[] {1, 2, 3}, "mp3"));
    StagedAudio staged = org.mockito.Mockito.mock(StagedAudio.class);
    when(audioStorage.stage(any())).thenReturn(staged);
    when(audioStorage.promote(staged))
        .thenReturn(new StoredAudio(STORAGE_KEY, "audio/mpeg", 3L, "checksum", 1040L));
    when(persistenceService.completeSuccess(
            MESSAGE_ID, STORAGE_KEY, AUDIO_URL, "CHILD_FRIENDLY_01", SPEED, TONE_PROFILE))
        .thenReturn(false);

    assertThatThrownBy(() -> service.generate(GUARDIAN_ID, MESSAGE_ID, request()))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(QuestionTtsErrorCode.TTS_GENERATION_IN_PROGRESS);

    verify(audioStorage).delete(STORAGE_KEY);
  }

  @Test
  void reportsConflictWhenGenerationInProgress() {
    authorizeQuestion();
    when(persistenceService.claim(MESSAGE_ID, "CHILD_FRIENDLY_01", SPEED, TONE_PROFILE))
        .thenReturn(
            new QuestionTtsClaimResult(
                QuestionTtsClaimResult.Action.IN_PROGRESS, MESSAGE_ID, SUBTITLE, null));

    assertThatThrownBy(() -> service.generate(GUARDIAN_ID, MESSAGE_ID, request()))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(QuestionTtsErrorCode.TTS_GENERATION_IN_PROGRESS);

    verifyNoInteractions(aiTtsClient, audioStorage);
  }

  @Test
  void throwsNotApplicableWhenNotQuestion() {
    when(messageRepository.findById(MESSAGE_ID)).thenReturn(Optional.of(message("OPTION_ANSWER")));
    authorizeChild();

    assertThatThrownBy(() -> service.generate(GUARDIAN_ID, MESSAGE_ID, request()))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(QuestionTtsErrorCode.TTS_NOT_APPLICABLE);

    verify(persistenceService, never()).claim(any(), any(), any(), any());
  }

  @Test
  void throwsAccessDeniedWhenGuardianNotRelated() {
    when(messageRepository.findById(MESSAGE_ID)).thenReturn(Optional.of(message("QUESTION")));
    when(conversationSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    when(drawingSessionRepository.findById(DRAWING_SESSION_ID))
        .thenReturn(Optional.of(drawingSession()));
    when(authorizationRepository.hasGuardianChildRelation(GUARDIAN_ID, CHILD_ID)).thenReturn(false);

    assertThatThrownBy(() -> service.generate(GUARDIAN_ID, MESSAGE_ID, request()))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_ACCESS_DENIED);

    verify(persistenceService, never()).claim(any(), any(), any(), any());
  }

  @Test
  void throwsNotFoundWhenMessageMissing() {
    when(messageRepository.findById(MESSAGE_ID)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.generate(GUARDIAN_ID, MESSAGE_ID, request()))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND);

    verifyNoInteractions(conversationSessionRepository, persistenceService);
  }

  private void authorizeQuestion() {
    when(messageRepository.findById(MESSAGE_ID)).thenReturn(Optional.of(message("QUESTION")));
    authorizeChild();
  }

  private void authorizeChild() {
    when(conversationSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session()));
    when(drawingSessionRepository.findById(DRAWING_SESSION_ID))
        .thenReturn(Optional.of(drawingSession()));
    when(authorizationRepository.hasGuardianChildRelation(GUARDIAN_ID, CHILD_ID)).thenReturn(true);
  }

  private TtsGenerateRequest request() {
    return new TtsGenerateRequest("CHILD_FRIENDLY_01", SPEED);
  }

  private ConversationSession session() {
    return ConversationSession.start(DRAWING_SESSION_ID, "LOWER_ELEMENTARY", 5, CREATED_AT);
  }

  private ConversationStartDrawingSession drawingSession() {
    ConversationStartDrawingSession drawingSession =
        instantiate(ConversationStartDrawingSession.class);
    ReflectionTestUtils.setField(drawingSession, "id", DRAWING_SESSION_ID);
    ReflectionTestUtils.setField(drawingSession, "childId", CHILD_ID);
    return drawingSession;
  }

  private ConversationHistoryMessage message(String messageType) {
    ConversationHistoryMessage message = instantiate(ConversationHistoryMessage.class);
    ReflectionTestUtils.setField(message, "id", MESSAGE_ID);
    ReflectionTestUtils.setField(message, "conversationSessionId", SESSION_ID);
    ReflectionTestUtils.setField(message, "senderType", "AI");
    ReflectionTestUtils.setField(message, "messageType", messageType);
    ReflectionTestUtils.setField(message, "rawText", SUBTITLE);
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
