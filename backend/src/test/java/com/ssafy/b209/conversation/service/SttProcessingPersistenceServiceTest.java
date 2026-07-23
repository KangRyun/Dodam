package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.SttVoiceAnswerMessage;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.SttVoiceAnswerMessageRepository;
import java.math.BigDecimal;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

/** 289 조건부 상태 선점과 DECIMAL(5,4) 결과 정규화를 검증한다. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class SttProcessingPersistenceServiceTest {
  private static final long MESSAGE_ID = 71L;
  private static final long SESSION_ID = 18L;

  @Mock private SttVoiceAnswerMessageRepository messageRepository;
  @Mock private ConversationSessionRepository sessionRepository;
  @Mock private ConversationSession session;

  private SttProcessingPersistenceService service;

  @BeforeEach
  void setUp() {
    service = new SttProcessingPersistenceService(messageRepository, sessionRepository);
    given(session.isConversing()).willReturn(true);
    given(session.getDifficultySnapshot()).willReturn("PRESCHOOL");
  }

  @Test
  void claimsOnlyPendingVoiceAnswer() {
    SttVoiceAnswerMessage pending = message("PENDING", null, null, false);
    given(messageRepository.findById(MESSAGE_ID)).willReturn(Optional.of(pending));
    given(sessionRepository.findByIdForUpdate(SESSION_ID)).willReturn(Optional.of(session));
    given(messageRepository.claimPending(MESSAGE_ID)).willReturn(1);

    SttClaimResult result = service.claim(MESSAGE_ID);

    assertThat(result.action()).isEqualTo(SttClaimResult.Action.CLAIMED);
    verify(messageRepository).claimPending(MESSAGE_ID);
  }

  @Test
  void doesNotClaimAlreadyProcessingMessage() {
    SttVoiceAnswerMessage processing = message("PROCESSING", null, null, false);
    given(messageRepository.findById(MESSAGE_ID)).willReturn(Optional.of(processing));
    given(sessionRepository.findByIdForUpdate(SESSION_ID)).willReturn(Optional.of(session));

    SttClaimResult result = service.claim(MESSAGE_ID);

    assertThat(result.action()).isEqualTo(SttClaimResult.Action.PROCESSING);
    verify(messageRepository, never()).claimPending(MESSAGE_ID);
  }

  @Test
  void replaysExistingSuccessWithoutClaimingAgain() {
    SttVoiceAnswerMessage success = message("SUCCESS", "기존 결과", new BigDecimal("0.9000"), false);
    given(messageRepository.findById(MESSAGE_ID)).willReturn(Optional.of(success));
    given(sessionRepository.findByIdForUpdate(SESSION_ID)).willReturn(Optional.of(session));

    SttClaimResult result = service.claim(MESSAGE_ID);

    assertThat(result.action()).isEqualTo(SttClaimResult.Action.SUCCESS);
    assertThat(result.sttText()).isEqualTo("기존 결과");
    verify(messageRepository, never()).claimPending(MESSAGE_ID);
  }

  @Test
  void storesNullConfidenceWhenWhisperDoesNotProvideIt() {
    SttVoiceAnswerMessage success = message("SUCCESS", "결과", null, false);
    given(messageRepository.findById(MESSAGE_ID)).willReturn(Optional.of(success));

    SttProcessingResult result = service.completeSuccess(MESSAGE_ID, "결과", null, false);

    ArgumentCaptor<BigDecimal> confidenceCaptor = ArgumentCaptor.forClass(BigDecimal.class);
    verify(messageRepository)
        .completeSuccess(
            org.mockito.ArgumentMatchers.eq(MESSAGE_ID),
            org.mockito.ArgumentMatchers.eq("결과"),
            confidenceCaptor.capture(),
            org.mockito.ArgumentMatchers.eq(false));
    assertThat(confidenceCaptor.getValue()).isNull();
    assertThat(result.confidence()).isNull();
  }

  private SttVoiceAnswerMessage message(
      String speechStatus, String text, BigDecimal confidence, boolean needsConfirmation) {
    SttVoiceAnswerMessage message = org.mockito.Mockito.mock(SttVoiceAnswerMessage.class);
    given(message.getId()).willReturn(MESSAGE_ID);
    given(message.getConversationSessionId()).willReturn(SESSION_ID);
    given(message.getParentMessageId()).willReturn(33L);
    given(message.getMessageSequence()).willReturn(4);
    given(message.getSenderType()).willReturn("CHILD");
    given(message.getMessageType()).willReturn("VOICE_ANSWER");
    given(message.getAudioStorageKey()).willReturn("2026/07/23/voice.wav");
    given(message.getSpeechStatus()).willReturn(speechStatus);
    given(message.getSttText()).willReturn(text);
    given(message.getSttConfidence()).willReturn(confidence);
    given(message.isNeedsGuardianConfirmation()).willReturn(needsConfirmation);
    return message;
  }
}
