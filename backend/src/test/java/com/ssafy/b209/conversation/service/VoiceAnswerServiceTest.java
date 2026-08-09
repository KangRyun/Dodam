package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.domain.VoiceAnswerMessage;
import com.ssafy.b209.conversation.dto.VoiceAnswerMetadata;
import com.ssafy.b209.conversation.dto.VoiceAnswerResponse;
import com.ssafy.b209.conversation.dto.VoiceAnswerStopReason;
import com.ssafy.b209.conversation.exception.VoiceAnswerErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerMessageRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.StagedAudio;
import com.ssafy.b209.storage.audio.StoredAudio;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** 288번 음성 답변의 저장 값·부모 질문·파일 보상 경계를 검증한다. */
@ExtendWith(MockitoExtension.class)
class VoiceAnswerServiceTest {
  private static final long GUARDIAN_ID = 10L;
  private static final long CONVERSATION_ID = 20L;
  private static final long DRAWING_SESSION_ID = 30L;
  private static final long CHILD_ID = 40L;
  private static final long QUESTION_ID = 50L;
  private static final String STORAGE_KEY = "2026/07/23/voice.wav";
  private static final String CHECKSUM = "a".repeat(64);

  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private VoiceAnswerAuthorizationRepository authorizationRepository;
  @Mock private VoiceAnswerMessageRepository messageRepository;
  @Mock private AudioStorage audioStorage;
  @Mock private ApplicationEventPublisher eventPublisher;
  @Mock private ConversationSession session;
  @Mock private ConversationStartDrawingSession drawingSession;
  @Mock private VoiceAnswerMessage question;
  @Mock private VoiceAnswerMessage savedMessage;
  @Mock private StagedAudio stagedAudio;
  @Mock private ConversationEventRecorder eventRecorder;

  private VoiceAnswerService service;

  @BeforeEach
  void setUp() {
    service =
        new VoiceAnswerService(
            conversationSessionRepository,
            drawingSessionRepository,
            authorizationRepository,
            messageRepository,
            audioStorage,
            eventRecorder,
            new ObjectMapper(),
            Clock.fixed(Instant.parse("2026-07-23T00:00:00Z"), ZoneOffset.UTC),
            eventPublisher);
  }

  @Test
  void persistsPendingChildVoiceAnswerWithParentAndChecksum() {
    givenAuthorizedLockedSession();
    given(messageRepository.findQuestionByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(question));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(audioStorage.promote(stagedAudio)).willReturn(storedAudio());
    given(savedMessage.getId()).willReturn(60L);
    given(savedMessage.getParentMessageId()).willReturn(QUESTION_ID);
    given(savedMessage.getMessageSequence()).willReturn(5);
    given(savedMessage.getSenderType()).willReturn("CHILD");
    given(savedMessage.getMessageType()).willReturn("VOICE_ANSWER");
    given(savedMessage.getSpeechStatus()).willReturn("PENDING");
    given(savedMessage.isNeedsGuardianConfirmation()).willReturn(false);
    given(messageRepository.saveAndFlush(any(VoiceAnswerMessage.class))).willReturn(savedMessage);

    ResponseEntity<?> response =
        service.persist(GUARDIAN_ID, CONVERSATION_ID, metadata(), stagedAudio);

    ArgumentCaptor<VoiceAnswerMessage> messageCaptor =
        ArgumentCaptor.forClass(VoiceAnswerMessage.class);
    verify(messageRepository).saveAndFlush(messageCaptor.capture());
    VoiceAnswerMessage message = messageCaptor.getValue();
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    assertThat(response.getBody()).isInstanceOf(ApiResponse.class);
    assertThat(((VoiceAnswerResponse) ((ApiResponse<?>) response.getBody()).data()).messageType())
        .isEqualTo("ANSWER_VOICE");
    assertThat(message.getConversationSessionId()).isEqualTo(CONVERSATION_ID);
    assertThat(message.getParentMessageId()).isEqualTo(QUESTION_ID);
    assertThat(message.getMessageSequence()).isEqualTo(5);
    assertThat(message.getSenderType()).isEqualTo("CHILD");
    assertThat(message.getMessageType()).isEqualTo("VOICE_ANSWER");
    assertThat(message.getRawText()).isNull();
    assertThat(message.getSttText()).isNull();
    assertThat(message.getSpeechStatus()).isEqualTo("PENDING");
    assertThat(ReflectionTestUtils.getField(message, "audioStorageKey")).isEqualTo(STORAGE_KEY);
    assertThat(ReflectionTestUtils.getField(message, "audioChecksumSha256")).isEqualTo(CHECKSUM);
  }

  @Test
  void publishesSttRequestEventForTheSavedMessage() {
    givenAuthorizedLockedSession();
    given(messageRepository.findQuestionByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(question));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(audioStorage.promote(stagedAudio)).willReturn(storedAudio());
    given(savedMessage.getId()).willReturn(60L);
    given(savedMessage.getParentMessageId()).willReturn(QUESTION_ID);
    given(savedMessage.getMessageSequence()).willReturn(5);
    given(savedMessage.getSenderType()).willReturn("CHILD");
    given(savedMessage.getMessageType()).willReturn("VOICE_ANSWER");
    given(savedMessage.getSpeechStatus()).willReturn("PENDING");
    given(savedMessage.isNeedsGuardianConfirmation()).willReturn(false);
    given(messageRepository.saveAndFlush(any(VoiceAnswerMessage.class))).willReturn(savedMessage);

    service.persist(GUARDIAN_ID, CONVERSATION_ID, metadata(), stagedAudio);

    verify(eventPublisher).publishEvent(new VoiceAnswerStoredEvent(60L));
  }

  @Test
  void doesNotPublishSttRequestEventWhenPersistenceFails() {
    givenAuthorizedLockedSession();
    given(messageRepository.findQuestionByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(question));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(audioStorage.promote(stagedAudio)).willReturn(storedAudio());
    given(messageRepository.saveAndFlush(any(VoiceAnswerMessage.class)))
        .willThrow(new DataIntegrityViolationException("sequence conflict"));

    assertThatThrownBy(() -> service.persist(GUARDIAN_ID, CONVERSATION_ID, metadata(), stagedAudio))
        .isInstanceOf(BusinessException.class);

    verify(eventPublisher, never()).publishEvent(any(VoiceAnswerStoredEvent.class));
  }

  @Test
  void rejectsParentMessageThatIsNotAQuestionInTheConversationBeforeFilePromotion() {
    givenAuthorizedLockedSession();
    given(messageRepository.findQuestionByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.empty());

    assertThatThrownBy(() -> service.persist(GUARDIAN_ID, CONVERSATION_ID, metadata(), stagedAudio))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(VoiceAnswerErrorCode.QUESTION_MESSAGE_NOT_FOUND));

    verify(audioStorage, never()).promote(any());
    verify(messageRepository, never()).saveAndFlush(any());
  }

  @Test
  void deletesPromotedFileWhenMessagePersistenceFails() {
    givenAuthorizedLockedSession();
    given(messageRepository.findQuestionByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(question));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(audioStorage.promote(stagedAudio)).willReturn(storedAudio());
    given(messageRepository.saveAndFlush(any(VoiceAnswerMessage.class)))
        .willThrow(new DataIntegrityViolationException("sequence conflict"));

    assertThatThrownBy(() -> service.persist(GUARDIAN_ID, CONVERSATION_ID, metadata(), stagedAudio))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(VoiceAnswerErrorCode.VOICE_ANSWER_STORAGE_CONFLICT));

    verify(audioStorage).delete(STORAGE_KEY);
  }

  @Test
  void deletesPromotedFileWhenTransactionRollsBackAfterSuccessfulPersistence() {
    givenAuthorizedLockedSession();
    given(messageRepository.findQuestionByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(question));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(audioStorage.promote(stagedAudio)).willReturn(storedAudio());
    given(messageRepository.saveAndFlush(any(VoiceAnswerMessage.class))).willReturn(savedMessage);
    given(savedMessage.getId()).willReturn(60L);
    given(savedMessage.getParentMessageId()).willReturn(QUESTION_ID);
    given(savedMessage.getMessageSequence()).willReturn(5);
    given(savedMessage.getSenderType()).willReturn("CHILD");
    given(savedMessage.getMessageType()).willReturn("VOICE_ANSWER");
    given(savedMessage.getSpeechStatus()).willReturn("PENDING");

    TransactionSynchronizationManager.initSynchronization();
    try {
      service.persist(GUARDIAN_ID, CONVERSATION_ID, metadata(), stagedAudio);
      TransactionSynchronizationManager.getSynchronizations()
          .forEach(sync -> sync.afterCompletion(TransactionSynchronization.STATUS_ROLLED_BACK));
    } finally {
      TransactionSynchronizationManager.clearSynchronization();
    }

    verify(audioStorage).delete(STORAGE_KEY);
  }

  /**
   * 음성 답변이 저장될 때 대화 행동 이벤트 훅이 실제로 불리는지 확인한다 (S15P11B209-973).
   *
   * <p><b>왜 이 테스트가 필요한가</b>: 적재기가 잘 저장하는지는 {@code ConversationEventMongoIntegrationTest}가 본다. 여기서
   * 지키는 것은 <b>이 흐름이 적재기를 부르는가</b>다. S15P11B209-902 에서는 저장 메서드가 동작했는데 아무도 부르지 않아 몇 주간 데이터가 비었고, 그때
   * 없던 것이 정확히 이 단언이다. 이 흐름은 음성 파일 저장소를 끼고 있어 관통 테스트로 옮기기 어려우므로 호출부를 여기서 못박는다.
   *
   * <p>넘기는 값이 <b>녹음 시각과 종료 사유뿐</b>인 것도 함께 확인한다. 전사 결과(sttText)는 커밋 후 289가 채우는 아이의 발화이며 행동 로그로 새면 안
   * 된다 (CLAUDE.md 9절).
   */
  @Test
  void recordsAVoiceAnswerEventWithRecordingWindowAndStopReasonOnly() {
    givenAuthorizedLockedSession();
    given(messageRepository.findQuestionByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(question));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(audioStorage.promote(stagedAudio)).willReturn(storedAudio());
    given(savedMessage.getId()).willReturn(60L);
    given(savedMessage.getMessageSequence()).willReturn(5);
    // 응답 조립이 이 값으로 공개 유형을 매핑한다. 비우면 매퍼의 switch 가 NPE 로 죽어, 검증 대상과 무관한 곳에서 실패한다.
    given(savedMessage.getMessageType()).willReturn("VOICE_ANSWER");
    given(messageRepository.saveAndFlush(any(VoiceAnswerMessage.class))).willReturn(savedMessage);

    service.persist(GUARDIAN_ID, CONVERSATION_ID, metadata(), stagedAudio);

    verify(eventRecorder)
        .recordVoiceAnswer(
            new ConversationEventContext(CONVERSATION_ID, CHILD_ID, DRAWING_SESSION_ID),
            QUESTION_ID,
            5,
            Instant.parse("2026-07-23T00:00:00Z"),
            Instant.parse("2026-07-23T00:00:01Z"),
            "USER_FINISH");
  }

  private void givenAuthorizedLockedSession() {
    given(conversationSessionRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(DRAWING_SESSION_ID);
    given(session.isConversing()).willReturn(true);
    given(drawingSessionRepository.findById(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(CHILD_ID);
    given(authorizationRepository.hasGuardianChildRelation(GUARDIAN_ID, CHILD_ID)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(CHILD_ID)).willReturn(true);
    given(authorizationRepository.hasVoiceProcessingConsent(CHILD_ID)).willReturn(true);
  }

  private VoiceAnswerMetadata metadata() {
    return new VoiceAnswerMetadata(
        QUESTION_ID,
        Instant.parse("2026-07-23T00:00:00Z"),
        Instant.parse("2026-07-23T00:00:01Z"),
        VoiceAnswerStopReason.USER_FINISH);
  }

  private StoredAudio storedAudio() {
    return new StoredAudio(STORAGE_KEY, "audio/wav", 64L, CHECKSUM, 1_000L);
  }
}
