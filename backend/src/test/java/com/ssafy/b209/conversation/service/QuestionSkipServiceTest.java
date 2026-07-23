package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.domain.SkipQuestionMessage;
import com.ssafy.b209.conversation.dto.QuestionSkipRequest;
import com.ssafy.b209.conversation.dto.QuestionSkipResponse;
import com.ssafy.b209.conversation.dto.SkipReason;
import com.ssafy.b209.conversation.exception.QuestionSkipErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.SkipQuestionMessageRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** 질문 건너뛰기의 검증 경계·건너뛰기 표시·그리기 복귀·멱등 재요청·오류 매핑을 검증한다. */
@ExtendWith(MockitoExtension.class)
class QuestionSkipServiceTest {
  private static final long GUARDIAN_ID = 10L;
  private static final long CONVERSATION_ID = 20L;
  private static final long DRAWING_SESSION_ID = 30L;
  private static final long CHILD_ID = 40L;
  private static final long QUESTION_ID = 50L;

  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private VoiceAnswerAuthorizationRepository authorizationRepository;
  @Mock private SkipQuestionMessageRepository messageRepository;
  @Mock private ConversationSession session;
  @Mock private ConversationStartDrawingSession drawingSession;
  @Mock private SkipQuestionMessage question;

  @InjectMocks private QuestionSkipService service;

  @Test
  void marksSkippedAndKeepsConversingWhenReturnToDrawingFalse() {
    givenAuthorizedConversingSession();
    givenQuestionWithoutAnswer();
    given(session.getQuestionCount()).willReturn(5);
    given(session.getMaxQuestionCount()).willReturn(10);
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.CONVERSING);

    QuestionSkipResponse response = service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false));

    verify(question).markSkipped();
    verify(messageRepository).save(question);
    verify(drawingSession, never()).moveToDrawing();
    assertThat(response.questionMessageId()).isEqualTo(QUESTION_ID);
    assertThat(response.isSkipped()).isTrue();
    assertThat(response.questionCount()).isEqualTo(5);
    assertThat(response.maxQuestionCount()).isEqualTo(10);
    assertThat(response.currentStage()).isEqualTo("CONVERSING");
  }

  @Test
  void movesToDrawingWhenReturnToDrawingTrue() {
    givenAuthorizedConversingSession();
    givenQuestionWithoutAnswer();
    given(session.getQuestionCount()).willReturn(5);
    given(session.getMaxQuestionCount()).willReturn(10);
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.DRAWING);

    QuestionSkipResponse response = service.skip(GUARDIAN_ID, CONVERSATION_ID, request(true));

    verify(question).markSkipped();
    verify(drawingSession).moveToDrawing();
    assertThat(response.currentStage()).isEqualTo("DRAWING");
    assertThat(response.questionCount()).isEqualTo(5);
  }

  @Test
  void isIdempotentOnRepeatedSkipRequest() {
    givenAuthorizedConversingSession();
    givenQuestionWithoutAnswer();
    given(session.getQuestionCount()).willReturn(5);
    given(session.getMaxQuestionCount()).willReturn(10);
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.CONVERSING);

    QuestionSkipResponse first = service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false));
    QuestionSkipResponse second = service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false));

    assertThat(second).isEqualTo(first);
    assertThat(second.isSkipped()).isTrue();
    verify(question, org.mockito.Mockito.times(2)).markSkipped();
  }

  @Test
  void rejectsMissingConversation() {
    given(conversationSessionRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.empty());

    assertThatThrownBy(() -> service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.CONVERSATION_NOT_FOUND));
    verify(messageRepository, never()).save(any());
  }

  @Test
  void rejectsGuardianWithoutChildRelation() {
    given(conversationSessionRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(DRAWING_SESSION_ID);
    given(drawingSessionRepository.findById(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(CHILD_ID);
    given(authorizationRepository.hasGuardianChildRelation(GUARDIAN_ID, CHILD_ID))
        .willReturn(false);

    assertThatThrownBy(() -> service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.CONVERSATION_ACCESS_DENIED));
    verify(messageRepository, never()).save(any());
  }

  @Test
  void rejectsWhenRequiredConsentMissing() {
    given(conversationSessionRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(DRAWING_SESSION_ID);
    given(drawingSessionRepository.findById(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(CHILD_ID);
    given(authorizationRepository.hasGuardianChildRelation(GUARDIAN_ID, CHILD_ID)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(CHILD_ID)).willReturn(false);

    assertThatThrownBy(() -> service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.CONSENT_REQUIRED));
  }

  @Test
  void rejectsCompletedConversation() {
    given(conversationSessionRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(DRAWING_SESSION_ID);
    given(drawingSessionRepository.findById(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(CHILD_ID);
    given(authorizationRepository.hasGuardianChildRelation(GUARDIAN_ID, CHILD_ID)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(CHILD_ID)).willReturn(true);
    given(session.isCompleted()).willReturn(true);

    assertThatThrownBy(() -> service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.CONVERSATION_ALREADY_COMPLETED));
  }

  @Test
  void rejectsWhenNotConversing() {
    given(conversationSessionRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(DRAWING_SESSION_ID);
    given(drawingSessionRepository.findById(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(CHILD_ID);
    given(authorizationRepository.hasGuardianChildRelation(GUARDIAN_ID, CHILD_ID)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(CHILD_ID)).willReturn(true);
    given(session.isCompleted()).willReturn(false);
    given(session.isConversing()).willReturn(false);

    assertThatThrownBy(() -> service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.CONVERSATION_NOT_CONVERSING));
  }

  @Test
  void rejectsQuestionThatIsNotInConversation() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(false);

    assertThatThrownBy(() -> service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.QUESTION_MESSAGE_NOT_FOUND));
    verify(messageRepository, never()).save(any());
  }

  @Test
  void rejectsQuestionThatIsAlreadyAnswered() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID)).willReturn(true);

    assertThatThrownBy(() -> service.skip(GUARDIAN_ID, CONVERSATION_ID, request(false)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.ANSWER_ALREADY_SUBMITTED));
    verify(messageRepository, never()).save(any());
  }

  private void givenAuthorizedConversingSession() {
    given(conversationSessionRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.of(session));
    given(session.getDrawingSessionId()).willReturn(DRAWING_SESSION_ID);
    given(drawingSessionRepository.findById(DRAWING_SESSION_ID))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getChildId()).willReturn(CHILD_ID);
    given(authorizationRepository.hasGuardianChildRelation(GUARDIAN_ID, CHILD_ID)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(CHILD_ID)).willReturn(true);
    given(session.isCompleted()).willReturn(false);
    given(session.isConversing()).willReturn(true);
  }

  private void givenQuestionWithoutAnswer() {
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .willReturn(false);
    given(messageRepository.findById(QUESTION_ID)).willReturn(Optional.of(question));
  }

  private QuestionSkipRequest request(boolean returnToDrawing) {
    return new QuestionSkipRequest(QUESTION_ID, SkipReason.CHILD_REQUEST, returnToDrawing);
  }
}
