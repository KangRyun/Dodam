package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.ConversationMessageSttStatusResponse;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.lang.reflect.Constructor;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

/** STT 상태 조회 서비스가 소유권을 검증하고 상태별로 변환 결과를 노출·은닉하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class ConversationMessageSttStatusQueryServiceTest {
  @Mock private ConversationHistoryMessageRepository messageRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private VoiceAnswerAuthorizationRepository authorizationRepository;

  private ConversationMessageSttStatusQueryService service;

  private static final LocalDateTime CREATED_AT = LocalDateTime.of(2026, 7, 21, 2, 36, 12);

  @BeforeEach
  void setUp() {
    service =
        new ConversationMessageSttStatusQueryService(
            messageRepository,
            conversationSessionRepository,
            drawingSessionRepository,
            authorizationRepository);
  }

  @Test
  void throwsWhenMessageMissing() {
    when(messageRepository.findById(804L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.getSttStatus(10L, 804L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND);

    verifyNoInteractions(conversationSessionRepository, authorizationRepository);
  }

  @Test
  void throwsWhenConversationSessionMissing() {
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("PENDING", null, null)));
    when(conversationSessionRepository.findById(800L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.getSttStatus(10L, 804L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND);

    verifyNoInteractions(authorizationRepository);
  }

  @Test
  void throwsWhenGuardianNotRelated() {
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("PENDING", null, null)));
    when(conversationSessionRepository.findById(800L)).thenReturn(Optional.of(session()));
    when(drawingSessionRepository.findById(100L)).thenReturn(Optional.of(drawingSession(1L)));
    when(authorizationRepository.hasGuardianChildRelation(10L, 1L)).thenReturn(false);

    assertThatThrownBy(() -> service.getSttStatus(10L, 804L))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_ACCESS_DENIED);
  }

  @Test
  void exposesSttResultWhenStatusSuccess() {
    authorizeChild();
    when(messageRepository.findById(804L))
        .thenReturn(
            Optional.of(voiceMessage("SUCCESS", "친구랑 같이 있어서 좋아", new BigDecimal("0.9100"))));

    ConversationMessageSttStatusResponse response = service.getSttStatus(10L, 804L);

    assertThat(response.messageId()).isEqualTo(804L);
    assertThat(response.parentMessageId()).isEqualTo(803L);
    assertThat(response.sequence()).isEqualTo(4);
    assertThat(response.senderType()).isEqualTo("CHILD");
    assertThat(response.messageType()).isEqualTo("ANSWER_VOICE");
    assertThat(response.rawText()).isNull();
    assertThat(response.speechStatus()).isEqualTo("SUCCESS");
    assertThat(response.sttText()).isEqualTo("친구랑 같이 있어서 좋아");
    assertThat(response.sttConfidence()).isEqualByComparingTo("0.91");
    assertThat(response.createdAt()).isEqualTo(CREATED_AT);
  }

  @Test
  void hidesSttResultWhenStatusNotSuccess() {
    authorizeChild();
    when(messageRepository.findById(804L))
        .thenReturn(
            Optional.of(voiceMessage("PROCESSING", "누출되면 안 되는 텍스트", new BigDecimal("0.4200"))));

    ConversationMessageSttStatusResponse response = service.getSttStatus(10L, 804L);

    assertThat(response.speechStatus()).isEqualTo("PROCESSING");
    assertThat(response.sttText()).isNull();
    assertThat(response.sttConfidence()).isNull();
  }

  @Test
  void hidesSttResultWhenStatusFailed() {
    authorizeChild();
    when(messageRepository.findById(804L))
        .thenReturn(Optional.of(voiceMessage("FAILED", null, null)));

    ConversationMessageSttStatusResponse response = service.getSttStatus(10L, 804L);

    assertThat(response.speechStatus()).isEqualTo("FAILED");
    assertThat(response.sttText()).isNull();
    assertThat(response.sttConfidence()).isNull();
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

  private ConversationHistoryMessage voiceMessage(
      String speechStatus, String sttText, BigDecimal sttConfidence) {
    ConversationHistoryMessage message = instantiate(ConversationHistoryMessage.class);
    ReflectionTestUtils.setField(message, "id", 804L);
    ReflectionTestUtils.setField(message, "conversationSessionId", 800L);
    ReflectionTestUtils.setField(message, "parentMessageId", 803L);
    ReflectionTestUtils.setField(message, "messageSequence", 4);
    ReflectionTestUtils.setField(message, "senderType", "CHILD");
    ReflectionTestUtils.setField(message, "messageType", "VOICE_ANSWER");
    ReflectionTestUtils.setField(message, "rawText", null);
    ReflectionTestUtils.setField(message, "sttText", sttText);
    ReflectionTestUtils.setField(message, "speechStatus", speechStatus);
    ReflectionTestUtils.setField(message, "sttConfidence", sttConfidence);
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
