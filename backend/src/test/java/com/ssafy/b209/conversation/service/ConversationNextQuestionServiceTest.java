package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.domain.ResponseMode;
import com.ssafy.b209.conversation.dto.BoundingBox;
import com.ssafy.b209.conversation.dto.DetectedObject;
import com.ssafy.b209.conversation.dto.GenerateQuestionCommand;
import com.ssafy.b209.conversation.dto.GeneratedQuestion;
import com.ssafy.b209.conversation.dto.NextQuestionRequest;
import com.ssafy.b209.conversation.dto.PreferredResponseMode;
import com.ssafy.b209.conversation.dto.QuestionOption;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** 283 공개 DTO 변환과 보호자 접근 경계를 검증한다. */
@ExtendWith(MockitoExtension.class)
class ConversationNextQuestionServiceTest {
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationMessageRepository conversationMessageRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private ConversationStartAuthorizationRepository authorizationRepository;
  @Mock private ChildRepository childRepository;
  @Mock private ConversationQuestionService questionService;
  @Mock private ConversationSession session;
  @Mock private ConversationStartDrawingSession drawingSession;
  @Mock private Child child;

  private ConversationNextQuestionService service;

  @BeforeEach
  void setUp() {
    service =
        new ConversationNextQuestionService(
            conversationSessionRepository,
            conversationMessageRepository,
            drawingSessionRepository,
            authorizationRepository,
            childRepository,
            questionService,
            Clock.fixed(Instant.parse("2026-07-22T00:00:00Z"), ZoneOffset.UTC));
  }

  @Test
  void mapsExternalModesWithoutLeakingInternalOptionAndReturnsFirstQuestion() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    given(questionService.generateQuestion(any()))
        .willReturn(
            new GeneratedQuestion(
                901L,
                "그림에서 무엇이 보이나요?",
                false,
                1,
                List.of(new QuestionOption("SUN", "해")),
                new DetectedObject("SUN", "해", 0.9, new BoundingBox(0.1, 0.2, 0.3, 0.4))));

    var response =
        service.generate(
            3L,
            11L,
            new NextQuestionRequest(
                700L, null, List.of(PreferredResponseMode.VOICE, PreferredResponseMode.EMOJI)));

    ArgumentCaptor<com.ssafy.b209.conversation.dto.GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.GenerateQuestionCommand.class);
    org.mockito.Mockito.verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().allowedResponseModes())
        .containsExactlyInAnyOrder(ResponseMode.VOICE, ResponseMode.OPTION);
    assertThat(commandCaptor.getValue().previousAnswerMessageId()).isNull();
    assertThat(response.messageType()).isEqualTo("QUESTION");
    assertThat(response.options().getFirst().type()).isEqualTo("OPTION");
    assertThat(response.targetObject().boundingBox().width()).isEqualTo(0.3);
  }

  @Test
  void rejectsGuardianWithoutChildRelation() {
    given(conversationSessionRepository.findById(11L)).willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(101L);
    given(drawingSessionRepository.findById(101L)).willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(7L);
    given(authorizationRepository.hasGuardianChildRelation(3L, 7L)).willReturn(false);

    assertThatThrownBy(
            () ->
                service.generate(
                    3L,
                    11L,
                    new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.TEXT))))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationErrorCode.CONVERSATION_ACCESS_DENIED));
  }

  @Test
  void passesSameConversationAnswerAsStoredQuestionParent() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    ConversationMessage answer = org.mockito.Mockito.mock(ConversationMessage.class);
    given(conversationMessageRepository.findByIdAndConversationSessionId(801L, 11L))
        .willReturn(Optional.of(answer));
    given(answer.isAnswerMessage()).willReturn(true);
    given(questionService.generateQuestion(any()))
        .willReturn(new GeneratedQuestion(902L, "무엇을 하고 있니?", false, 2, List.of(), null));

    service.generate(
        3L, 11L, new NextQuestionRequest(700L, 801L, List.of(PreferredResponseMode.TEXT)));

    ArgumentCaptor<GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(GenerateQuestionCommand.class);
    verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().previousAnswerMessageId()).isEqualTo(801L);
  }

  @Test
  void rejectsPreviousAnswerFromAnotherConversation() {
    stubAuthorizedConversation(false, true, true);
    given(conversationMessageRepository.findByIdAndConversationSessionId(801L, 11L))
        .willReturn(Optional.empty());

    assertBusinessError(
        () ->
            service.generate(
                3L, 11L, new NextQuestionRequest(700L, 801L, List.of(PreferredResponseMode.TEXT))),
        ConversationErrorCode.QUESTION_MESSAGE_NOT_FOUND);

    verify(questionService, never()).generateQuestion(any());
  }

  @Test
  void rejectsQuestionMessageAsPreviousAnswer() {
    stubAuthorizedConversation(false, true, true);
    ConversationMessage question = org.mockito.Mockito.mock(ConversationMessage.class);
    given(conversationMessageRepository.findByIdAndConversationSessionId(801L, 11L))
        .willReturn(Optional.of(question));
    given(question.isAnswerMessage()).willReturn(false);

    assertBusinessError(
        () ->
            service.generate(
                3L, 11L, new NextQuestionRequest(700L, 801L, List.of(PreferredResponseMode.TEXT))),
        ConversationErrorCode.QUESTION_MESSAGE_NOT_FOUND);

    verify(questionService, never()).generateQuestion(any());
  }

  @Test
  void rejectsCompletedConversation() {
    stubAuthorizedConversation(true, false, true);

    assertBusinessError(
        () -> service.generate(3L, 11L, request()),
        ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);
  }

  @Test
  void rejectsFailedConversationWithInvalidStateTransition() {
    stubAuthorizedConversation(false, false, true);

    assertBusinessError(
        () -> service.generate(3L, 11L, request()),
        ConversationStartErrorCode.INVALID_STATE_TRANSITION);
  }

  @Test
  void rejectsQuestionLimitReached() {
    stubAuthorizedConversation(false, true, false);

    assertBusinessError(
        () -> service.generate(3L, 11L, request()), ConversationErrorCode.QUESTION_LIMIT_REACHED);
  }

  @Test
  void rejectsGuardianWithoutRequiredConsent() {
    given(conversationSessionRepository.findById(11L)).willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(101L);
    given(drawingSessionRepository.findById(101L)).willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(7L);
    given(authorizationRepository.hasGuardianChildRelation(3L, 7L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(7L)).willReturn(false);

    assertBusinessError(
        () -> service.generate(3L, 11L, request()),
        ConversationErrorCode.CONVERSATION_ACCESS_DENIED);
  }

  private void stubAuthorizedConversation(boolean completed, boolean conversing, boolean canAsk) {
    given(conversationSessionRepository.findById(11L)).willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(101L);
    given(drawingSessionRepository.findById(101L)).willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(7L);
    given(authorizationRepository.hasGuardianChildRelation(3L, 7L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(7L)).willReturn(true);
    given(session.isCompleted()).willReturn(completed);
    if (completed) {
      return;
    }
    given(session.isConversing()).willReturn(conversing);
    if (!conversing) {
      return;
    }
    given(session.canAskQuestion()).willReturn(canAsk);
  }

  private void stubChildContext() {
    given(childRepository.findById(7L)).willReturn(Optional.of(child));
    given(child.ageOn(any(LocalDate.class))).willReturn(8);
  }

  private NextQuestionRequest request() {
    return new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.TEXT));
  }

  private void assertBusinessError(
      Runnable action, com.ssafy.b209.global.response.ErrorCode expected) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
