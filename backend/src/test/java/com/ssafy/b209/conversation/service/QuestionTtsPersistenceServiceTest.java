package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.domain.QuestionTtsMessage;
import com.ssafy.b209.conversation.dto.TtsToneProfile;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.exception.QuestionTtsErrorCode;
import com.ssafy.b209.conversation.repository.QuestionTtsMessageRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.lang.reflect.Constructor;
import java.math.BigDecimal;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

/** 질문 TTS 선점 서비스가 캐시 히트·선점·진행 중·경합 상태를 조건부 갱신으로 판정하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class QuestionTtsPersistenceServiceTest {
  private static final Long MESSAGE_ID = 803L;
  private static final String STORAGE_KEY = "2026/07/24/2f0b8f5e-tts.mp3";
  private static final BigDecimal SPEED = new BigDecimal("0.95");
  private static final TtsToneProfile TONE_PROFILE = TtsToneProfile.CHARACTER_DEFAULT_V1;

  @Mock private QuestionTtsMessageRepository messageRepository;

  private QuestionTtsPersistenceService service;

  @BeforeEach
  void setUp() {
    service = new QuestionTtsPersistenceService(messageRepository);
  }

  @Test
  void returnsCacheHitWhenSuccessAudioExists() {
    when(messageRepository.findById(MESSAGE_ID))
        .thenReturn(Optional.of(message("SUCCESS", STORAGE_KEY, "FABLE", SPEED)));

    QuestionTtsClaimResult result = service.claim(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE);

    assertThat(result.action()).isEqualTo(QuestionTtsClaimResult.Action.CACHE_HIT);
    assertThat(result.audioStorageKey()).isEqualTo(STORAGE_KEY);
    verify(messageRepository, never()).claimForSynthesis(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE.name());
  }

  @Test
  void returnsInProgressWhenProcessing() {
    when(messageRepository.findById(MESSAGE_ID))
        .thenReturn(Optional.of(message("PROCESSING", null, "FABLE", SPEED)));

    QuestionTtsClaimResult result = service.claim(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE);

    assertThat(result.action()).isEqualTo(QuestionTtsClaimResult.Action.IN_PROGRESS);
    verify(messageRepository, never()).claimForSynthesis(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE.name());
  }

  @Test
  void claimsWhenStatusEmpty() {
    when(messageRepository.findById(MESSAGE_ID))
        .thenReturn(Optional.of(message(null, null, null, null)));
    when(messageRepository.claimForSynthesis(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE.name()))
        .thenReturn(1);

    QuestionTtsClaimResult result = service.claim(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE);

    assertThat(result.action()).isEqualTo(QuestionTtsClaimResult.Action.CLAIMED);
    assertThat(result.subtitle()).isEqualTo("이 그림에서 무엇이 보이니?");
  }

  @Test
  void returnsCacheHitWhenLostRaceToSuccess() {
    when(messageRepository.findById(MESSAGE_ID))
        .thenReturn(Optional.of(message("FAILED", null, null, null)))
        .thenReturn(Optional.of(message("SUCCESS", STORAGE_KEY, "FABLE", SPEED)));
    when(messageRepository.claimForSynthesis(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE.name()))
        .thenReturn(0);

    QuestionTtsClaimResult result = service.claim(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE);

    assertThat(result.action()).isEqualTo(QuestionTtsClaimResult.Action.CACHE_HIT);
  }

  @Test
  void returnsInProgressWhenLostRaceToProcessing() {
    when(messageRepository.findById(MESSAGE_ID))
        .thenReturn(Optional.of(message(null, null, null, null)))
        .thenReturn(Optional.of(message("PROCESSING", null, "FABLE", SPEED)));
    when(messageRepository.claimForSynthesis(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE.name()))
        .thenReturn(0);

    QuestionTtsClaimResult result = service.claim(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE);

    assertThat(result.action()).isEqualTo(QuestionTtsClaimResult.Action.IN_PROGRESS);
  }

  @Test
  void throwsNotFoundWhenMissing() {
    when(messageRepository.findById(MESSAGE_ID)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.claim(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND);
  }

  @Test
  void throwsNotApplicableWhenNotAiQuestion() {
    QuestionTtsMessage optionAnswer = message(null, null, null, null);
    ReflectionTestUtils.setField(optionAnswer, "senderType", "CHILD");
    ReflectionTestUtils.setField(optionAnswer, "messageType", "OPTION_ANSWER");
    when(messageRepository.findById(MESSAGE_ID)).thenReturn(Optional.of(optionAnswer));

    assertThatThrownBy(() -> service.claim(MESSAGE_ID, "FABLE", SPEED, TONE_PROFILE))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(QuestionTtsErrorCode.TTS_NOT_APPLICABLE);
  }

  @Test
  void completeSuccessReportsAppliedUpdate() {
    when(messageRepository.completeSuccess(
            MESSAGE_ID, STORAGE_KEY, "/url", "FABLE", SPEED, TONE_PROFILE.name()))
        .thenReturn(1);

    assertThat(
            service.completeSuccess(
                MESSAGE_ID, STORAGE_KEY, "/url", "FABLE", SPEED, TONE_PROFILE))
        .isTrue();
  }

  @Test
  void completeSuccessReportsLostUpdate() {
    when(messageRepository.completeSuccess(
            MESSAGE_ID, STORAGE_KEY, "/url", "FABLE", SPEED, TONE_PROFILE.name()))
        .thenReturn(0);

    assertThat(
            service.completeSuccess(
                MESSAGE_ID, STORAGE_KEY, "/url", "FABLE", SPEED, TONE_PROFILE))
        .isFalse();
  }

  @Test
  void replacesCacheWhenExistingAudioWasGeneratedWithAnotherVoice() {
    when(messageRepository.findById(MESSAGE_ID))
        .thenReturn(Optional.of(message("SUCCESS", STORAGE_KEY, "FABLE", SPEED)));
    when(messageRepository.claimForSynthesis(MESSAGE_ID, "NOVA", SPEED, TONE_PROFILE.name()))
        .thenReturn(1);

    QuestionTtsClaimResult result = service.claim(MESSAGE_ID, "NOVA", SPEED, TONE_PROFILE);

    assertThat(result.action()).isEqualTo(QuestionTtsClaimResult.Action.CLAIMED);
  }

  @Test
  void replacesCacheWhenExistingAudioWasGeneratedAtAnotherSpeed() {
    BigDecimal fasterSpeed = new BigDecimal("1.00");
    when(messageRepository.findById(MESSAGE_ID))
        .thenReturn(Optional.of(message("SUCCESS", STORAGE_KEY, "FABLE", SPEED)));
    when(
            messageRepository.claimForSynthesis(
                MESSAGE_ID, "FABLE", fasterSpeed, TONE_PROFILE.name()))
        .thenReturn(1);

    QuestionTtsClaimResult result =
        service.claim(MESSAGE_ID, "FABLE", fasterSpeed, TONE_PROFILE);

    assertThat(result.action()).isEqualTo(QuestionTtsClaimResult.Action.CLAIMED);
  }

  @Test
  void replacesCacheWhenExistingAudioWasGeneratedWithAnotherToneProfile() {
    when(messageRepository.findById(MESSAGE_ID))
        .thenReturn(Optional.of(message("SUCCESS", STORAGE_KEY, "FABLE", SPEED)));
    when(
            messageRepository.claimForSynthesis(
                MESSAGE_ID,
                "FABLE",
                SPEED,
                TtsToneProfile.CHARACTER_CELEBRATING_V1.name()))
        .thenReturn(1);

    QuestionTtsClaimResult result =
        service.claim(
            MESSAGE_ID, "FABLE", SPEED, TtsToneProfile.CHARACTER_CELEBRATING_V1);

    assertThat(result.action()).isEqualTo(QuestionTtsClaimResult.Action.CLAIMED);
  }

  private QuestionTtsMessage message(
      String speechStatus, String audioStorageKey, String ttsVoice, BigDecimal ttsSpeed) {
    QuestionTtsMessage message = instantiate(QuestionTtsMessage.class);
    ReflectionTestUtils.setField(message, "id", MESSAGE_ID);
    ReflectionTestUtils.setField(message, "conversationSessionId", 800L);
    ReflectionTestUtils.setField(message, "senderType", "AI");
    ReflectionTestUtils.setField(message, "messageType", "QUESTION");
    ReflectionTestUtils.setField(message, "rawText", "이 그림에서 무엇이 보이니?");
    ReflectionTestUtils.setField(message, "audioStorageKey", audioStorageKey);
    ReflectionTestUtils.setField(message, "speechStatus", speechStatus);
    ReflectionTestUtils.setField(message, "ttsVoice", ttsVoice);
    ReflectionTestUtils.setField(message, "ttsSpeed", ttsSpeed);
    ReflectionTestUtils.setField(message, "ttsToneProfile", TONE_PROFILE.name());
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
