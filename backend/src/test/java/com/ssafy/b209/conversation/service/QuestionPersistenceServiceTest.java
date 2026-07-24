package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.dto.BoundingBox;
import com.ssafy.b209.conversation.dto.DetectedObject;
import com.ssafy.b209.conversation.dto.QuestionOption;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.repository.ConversationMessageOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageTargetRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class QuestionPersistenceServiceTest {

  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationMessageRepository conversationMessageRepository;
  @Mock private ConversationMessageOptionRepository conversationMessageOptionRepository;
  @Mock private ConversationMessageTargetRepository conversationMessageTargetRepository;

  private QuestionPersistenceService service;
  private ConversationSession session;

  @BeforeEach
  void setUp() {
    service =
        new QuestionPersistenceService(
            conversationSessionRepository,
            conversationMessageRepository,
            conversationMessageOptionRepository,
            conversationMessageTargetRepository);
    session = mock(ConversationSession.class);
    given(session.isConversing()).willReturn(true);
    given(session.isCompleted()).willReturn(false);
    given(session.canAskQuestion()).willReturn(true);
    given(conversationSessionRepository.findByIdForUpdate(1L)).willReturn(Optional.of(session));
  }

  @Test
  void locksSessionThenAllocatesNextSequenceAndIncreasesQuestionCount() {
    given(conversationMessageRepository.findMaxMessageSequenceByConversationSessionId(1L))
        .willReturn(4);
    given(conversationMessageRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationMessage message = invocation.getArgument(0);
              ReflectionTestUtils.setField(message, "id", 30L);
              return message;
            });

    service.save(
        1L,
        new QuestionCandidate(
            "안전한 질문", List.of(new QuestionOption("A", "선택지")), null, null, false));

    ArgumentCaptor<ConversationMessage> messageCaptor =
        ArgumentCaptor.forClass(ConversationMessage.class);
    verify(conversationSessionRepository).findByIdForUpdate(1L);
    verify(conversationMessageRepository).saveAndFlush(messageCaptor.capture());
    verify(session).increaseQuestionCount();
    org.assertj.core.api.Assertions.assertThat(messageCaptor.getValue().getMessageSequence())
        .isEqualTo(5);
    org.assertj.core.api.Assertions.assertThat(messageCaptor.getValue().getParentMessageId())
        .isNull();
  }

  @Test
  void savesValidatedPreviousAnswerAsQuestionParent() {
    ConversationMessage answer = mock(ConversationMessage.class);
    given(conversationMessageRepository.findMaxMessageSequenceByConversationSessionId(1L))
        .willReturn(1);
    given(conversationMessageRepository.findByIdAndConversationSessionId(44L, 1L))
        .willReturn(Optional.of(answer));
    given(answer.isAnswerMessage()).willReturn(true);
    given(conversationMessageRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationMessage message = invocation.getArgument(0);
              ReflectionTestUtils.setField(message, "id", 32L);
              return message;
            });

    service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, 44L));

    ArgumentCaptor<ConversationMessage> messageCaptor =
        ArgumentCaptor.forClass(ConversationMessage.class);
    verify(conversationMessageRepository).saveAndFlush(messageCaptor.capture());
    org.assertj.core.api.Assertions.assertThat(messageCaptor.getValue().getParentMessageId())
        .isEqualTo(44L);
  }

  @Test
  void rejectsSecondQuestionThatReusesTheSameParentAnswer() {
    ConversationMessage answer = mock(ConversationMessage.class);
    given(conversationMessageRepository.findByIdAndConversationSessionId(44L, 1L))
        .willReturn(Optional.of(answer));
    given(answer.isAnswerMessage()).willReturn(true);
    given(conversationMessageRepository.existsQuestionByParentMessageId(1L, 44L)).willReturn(true);

    assertBusinessError(
        () -> service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, 44L)),
        ConversationErrorCode.QUESTION_STORAGE_CONFLICT);

    verify(conversationMessageRepository, never())
        .findMaxMessageSequenceByConversationSessionId(any());
    verify(conversationMessageRepository, never()).saveAndFlush(any());
    verify(session, never()).increaseQuestionCount();
  }

  @Test
  void allowsFirstQuestionWithoutParentAnswerWithoutDuplicateCheck() {
    given(conversationMessageRepository.findMaxMessageSequenceByConversationSessionId(1L))
        .willReturn(0);
    given(conversationMessageRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationMessage message = invocation.getArgument(0);
              ReflectionTestUtils.setField(message, "id", 40L);
              return message;
            });

    service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, null));

    verify(conversationMessageRepository, never()).existsQuestionByParentMessageId(any(), any());
    verify(conversationMessageRepository).saveAndFlush(any());
    verify(session).increaseQuestionCount();
  }

  @Test
  void rejectsNonAnswerParentWithoutSavingQuestion() {
    ConversationMessage question = mock(ConversationMessage.class);
    given(conversationMessageRepository.findByIdAndConversationSessionId(44L, 1L))
        .willReturn(Optional.of(question));
    given(question.isAnswerMessage()).willReturn(false);

    assertBusinessError(
        () -> service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, 44L)),
        ConversationErrorCode.QUESTION_MESSAGE_NOT_FOUND);

    verify(conversationMessageRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsSaveAfterConcurrentRequestConsumesLastQuestion() {
    given(session.canAskQuestion()).willReturn(false);

    assertBusinessError(
        () -> service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false)),
        ConversationErrorCode.QUESTION_LIMIT_REACHED);

    verify(conversationMessageRepository, never())
        .findMaxMessageSequenceByConversationSessionId(any());
    verify(conversationMessageRepository, never()).saveAndFlush(any());
  }

  @Test
  void savesOptionAndTargetSnapshotsInTheSameTransaction() {
    given(conversationMessageRepository.findMaxMessageSequenceByConversationSessionId(1L))
        .willReturn(0);
    given(conversationMessageRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationMessage message = invocation.getArgument(0);
              ReflectionTestUtils.setField(message, "id", 31L);
              return message;
            });

    service.save(
        1L,
        new QuestionCandidate(
            "안전한 질문",
            List.of(new QuestionOption("TREE", "나무")),
            new DetectedObject("TREE", "나무", 0.9, new BoundingBox(0.1, 0.2, 0.3, 0.4)),
            null,
            false));

    verify(conversationMessageOptionRepository).saveAll(any());
    verify(conversationMessageTargetRepository).save(any());
  }

  private void assertBusinessError(Runnable action, ConversationErrorCode expected) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                org.assertj.core.api.Assertions.assertThat(exception.getErrorCode())
                    .isEqualTo(expected));
  }
}
