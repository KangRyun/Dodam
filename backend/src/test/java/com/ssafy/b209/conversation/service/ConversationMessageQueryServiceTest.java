package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationHistoryOption;
import com.ssafy.b209.conversation.domain.ConversationHistoryTarget;
import com.ssafy.b209.conversation.domain.ConversationMessageSelectedOption;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.ConversationMessagePageResponse;
import com.ssafy.b209.conversation.dto.ConversationMessageResponse;
import com.ssafy.b209.conversation.exception.ConversationMessageListErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationHistoryOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationHistoryTargetRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageSelectedOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.lang.reflect.Constructor;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.util.ReflectionTestUtils;

/** 대화 내역 조회 서비스가 소유권을 검증하고 메시지 유형별 필드를 조립하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class ConversationMessageQueryServiceTest {
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private VoiceAnswerAuthorizationRepository authorizationRepository;
  @Mock private ConversationHistoryMessageRepository messageRepository;
  @Mock private ConversationHistoryOptionRepository optionRepository;
  @Mock private ConversationHistoryTargetRepository targetRepository;
  @Mock private ConversationMessageSelectedOptionRepository selectedOptionRepository;

  private ConversationMessageQueryService service;

  private static final LocalDateTime CREATED_AT = LocalDateTime.of(2026, 7, 21, 2, 36, 0);

  @BeforeEach
  void setUp() {
    service =
        new ConversationMessageQueryService(
            conversationSessionRepository,
            drawingSessionRepository,
            authorizationRepository,
            messageRepository,
            optionRepository,
            targetRepository,
            selectedOptionRepository);
  }

  @Test
  void throwsWhenConversationMissing() {
    when(conversationSessionRepository.findById(800L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.getMessages(10L, 800L, 0, 50, null))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageListErrorCode.CONVERSATION_NOT_FOUND);

    verifyNoInteractions(messageRepository, optionRepository, targetRepository);
  }

  @Test
  void throwsWhenGuardianNotRelated() {
    when(conversationSessionRepository.findById(800L)).thenReturn(Optional.of(session()));
    when(drawingSessionRepository.findById(100L)).thenReturn(Optional.of(drawingSession(1L)));
    when(authorizationRepository.hasGuardianChildRelation(10L, 1L)).thenReturn(false);

    assertThatThrownBy(() -> service.getMessages(10L, 800L, 0, 50, null))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageListErrorCode.CONVERSATION_ACCESS_DENIED);

    verifyNoInteractions(messageRepository);
  }

  @Test
  void assemblesQuestionVoiceAndOptionMessagesInSequenceOrder() {
    when(conversationSessionRepository.findById(800L)).thenReturn(Optional.of(session()));
    when(drawingSessionRepository.findById(100L)).thenReturn(Optional.of(drawingSession(1L)));
    when(authorizationRepository.hasGuardianChildRelation(10L, 1L)).thenReturn(true);

    ConversationHistoryMessage question =
        message(803L, null, 3, "AI", "QUESTION", "이 사람 기분은?", null, null, null, false, false);
    ConversationHistoryMessage voice =
        message(
            804L,
            803L,
            4,
            "CHILD",
            "VOICE_ANSWER",
            null,
            "친구랑 같이 있어서 좋아",
            "SUCCESS",
            new BigDecimal("0.9100"),
            false,
            false);
    ConversationHistoryMessage option =
        message(805L, 803L, 5, "CHILD", "OPTION_ANSWER", null, null, null, null, false, false);

    when(messageRepository.findPage(800L, null, PageRequest.of(0, 50)))
        .thenReturn(new PageImpl<>(List.of(question, voice, option), PageRequest.of(0, 50), 3));
    when(optionRepository
            .findByConversationMessageIdInOrderByConversationMessageIdAscDisplayOrderAsc(any()))
        .thenReturn(
            List.of(option(11L, 803L, "happy", "EMOTION", "HAPPY", "기뻐요", "🙂", (short) 0)));
    when(targetRepository.findByConversationMessageIdIn(any()))
        .thenReturn(List.of(target(803L, "PERSON", "사람")));
    when(selectedOptionRepository.findByAnswerMessageIdInOrderByAnswerMessageIdAscSelectionOrderAsc(
            any()))
        .thenReturn(
            List.of(ConversationMessageSelectedOption.of(805L, 803L, 11L, "기뻐요", (short) 0)));
    when(optionRepository.findByIdIn(any()))
        .thenReturn(
            List.of(option(11L, 803L, "happy", "EMOTION", "HAPPY", "기뻐요", "🙂", (short) 0)));

    ConversationMessagePageResponse response = service.getMessages(10L, 800L, 0, 50, null);

    assertThat(response.content()).hasSize(3);
    assertThat(response.totalElements()).isEqualTo(3);
    assertThat(response.page()).isZero();
    assertThat(response.hasNext()).isFalse();
    assertThat(response.content())
        .extracting(ConversationMessageResponse::sequence)
        .containsExactly(3, 4, 5);

    ConversationMessageResponse questionResponse = response.content().get(0);
    assertThat(questionResponse.messageType()).isEqualTo("QUESTION");
    assertThat(questionResponse.options()).hasSize(1);
    assertThat(questionResponse.options().get(0).optionId()).isEqualTo("happy");
    assertThat(questionResponse.options().get(0).emoji()).isEqualTo("🙂");
    assertThat(questionResponse.targetObject()).isNotNull();
    assertThat(questionResponse.targetObject().objectCode()).isEqualTo("PERSON");
    assertThat(questionResponse.targetObject().boundingBox().width()).isEqualTo(0.25d);
    assertThat(questionResponse.selectedResponse()).isNull();

    ConversationMessageResponse voiceResponse = response.content().get(1);
    assertThat(voiceResponse.messageType()).isEqualTo("ANSWER_VOICE");
    assertThat(voiceResponse.sttText()).isEqualTo("친구랑 같이 있어서 좋아");
    assertThat(voiceResponse.speechStatus()).isEqualTo("SUCCESS");
    assertThat(voiceResponse.sttConfidence()).isEqualByComparingTo("0.91");
    assertThat(voiceResponse.options()).isEmpty();
    assertThat(voiceResponse.targetObject()).isNull();
    assertThat(voiceResponse.selectedResponse()).isNull();

    ConversationMessageResponse optionResponse = response.content().get(2);
    assertThat(optionResponse.messageType()).isEqualTo("ANSWER_OPTION");
    assertThat(optionResponse.selectedResponse()).isNotNull();
    assertThat(optionResponse.selectedResponse().selectedOptions()).hasSize(1);
    assertThat(optionResponse.selectedResponse().selectedOptions().get(0).optionId())
        .isEqualTo("happy");
    assertThat(optionResponse.selectedResponse().selectedOptions().get(0).labelSnapshot())
        .isEqualTo("기뻐요");
    assertThat(optionResponse.selectedResponse().directText()).isNull();
    assertThat(optionResponse.options()).isEmpty();
    assertThat(optionResponse.targetObject()).isNull();
  }

  @Test
  void returnsEmptyContentWithoutRelationQueriesWhenPageEmpty() {
    when(conversationSessionRepository.findById(800L)).thenReturn(Optional.of(session()));
    when(drawingSessionRepository.findById(100L)).thenReturn(Optional.of(drawingSession(1L)));
    when(authorizationRepository.hasGuardianChildRelation(10L, 1L)).thenReturn(true);
    when(messageRepository.findPage(800L, 5, PageRequest.of(1, 50)))
        .thenReturn(new PageImpl<>(List.of(), PageRequest.of(1, 50), 5));

    ConversationMessagePageResponse response = service.getMessages(10L, 800L, 1, 50, 5);

    assertThat(response.content()).isEmpty();
    assertThat(response.page()).isEqualTo(1);
    verifyNoInteractions(optionRepository, targetRepository, selectedOptionRepository);
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

  private ConversationHistoryMessage message(
      Long id,
      Long parentId,
      int sequence,
      String senderType,
      String messageType,
      String rawText,
      String sttText,
      String speechStatus,
      BigDecimal sttConfidence,
      boolean needsGuardianConfirmation,
      boolean skipped) {
    ConversationHistoryMessage message = instantiate(ConversationHistoryMessage.class);
    ReflectionTestUtils.setField(message, "id", id);
    ReflectionTestUtils.setField(message, "conversationSessionId", 800L);
    ReflectionTestUtils.setField(message, "parentMessageId", parentId);
    ReflectionTestUtils.setField(message, "messageSequence", sequence);
    ReflectionTestUtils.setField(message, "senderType", senderType);
    ReflectionTestUtils.setField(message, "messageType", messageType);
    ReflectionTestUtils.setField(message, "rawText", rawText);
    ReflectionTestUtils.setField(message, "sttText", sttText);
    ReflectionTestUtils.setField(message, "speechStatus", speechStatus);
    ReflectionTestUtils.setField(message, "sttConfidence", sttConfidence);
    ReflectionTestUtils.setField(message, "needsGuardianConfirmation", needsGuardianConfirmation);
    ReflectionTestUtils.setField(message, "skipped", skipped);
    ReflectionTestUtils.setField(message, "createdAt", CREATED_AT);
    return message;
  }

  private ConversationHistoryOption option(
      Long id,
      Long conversationMessageId,
      String optionKey,
      String optionType,
      String optionValue,
      String label,
      String emoji,
      short displayOrder) {
    ConversationHistoryOption option = instantiate(ConversationHistoryOption.class);
    ReflectionTestUtils.setField(option, "id", id);
    ReflectionTestUtils.setField(option, "conversationMessageId", conversationMessageId);
    ReflectionTestUtils.setField(option, "optionKey", optionKey);
    ReflectionTestUtils.setField(option, "optionType", optionType);
    ReflectionTestUtils.setField(option, "optionValue", optionValue);
    ReflectionTestUtils.setField(option, "label", label);
    ReflectionTestUtils.setField(option, "emoji", emoji);
    ReflectionTestUtils.setField(option, "displayOrder", displayOrder);
    return option;
  }

  private ConversationHistoryTarget target(
      Long conversationMessageId, String objectCode, String objectName) {
    ConversationHistoryTarget target = instantiate(ConversationHistoryTarget.class);
    ReflectionTestUtils.setField(target, "conversationMessageId", conversationMessageId);
    ReflectionTestUtils.setField(target, "objectCode", objectCode);
    ReflectionTestUtils.setField(target, "objectName", objectName);
    ReflectionTestUtils.setField(target, "bboxX", new BigDecimal("0.150000"));
    ReflectionTestUtils.setField(target, "bboxY", new BigDecimal("0.200000"));
    ReflectionTestUtils.setField(target, "bboxWidth", new BigDecimal("0.250000"));
    ReflectionTestUtils.setField(target, "bboxHeight", new BigDecimal("0.500000"));
    return target;
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
