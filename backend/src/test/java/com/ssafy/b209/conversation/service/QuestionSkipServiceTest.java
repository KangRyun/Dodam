package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.SkippableQuestionMessage;
import com.ssafy.b209.conversation.dto.SkipQuestionRequest;
import com.ssafy.b209.conversation.dto.SkipQuestionResponse;
import com.ssafy.b209.conversation.exception.QuestionSkipErrorCode;
import com.ssafy.b209.conversation.repository.ConversationEndAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.SkippableQuestionMessageRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.BeanUtils;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class QuestionSkipServiceTest {

  private static final Long GUARDIAN_ID = 7L;
  private static final Long CONVERSATION_ID = 20L;
  private static final Long QUESTION_ID = 803L;

  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private ConversationEndAuthorizationRepository authorizationRepository;
  @Mock private ConversationSessionRepository conversationRepository;
  @Mock private SkippableQuestionMessageRepository questionRepository;
  @Mock private ConversationSession conversation;

  private QuestionSkipService service;

  @BeforeEach
  void setUp() {
    service =
        new QuestionSkipService(
            currentUserResolver,
            authorizationRepository,
            conversationRepository,
            questionRepository);
  }

  @Test
  void marksQuestionAsSkipped() {
    SkippableQuestionMessage question = message("QUESTION", false);
    givenConversingAccess();
    given(questionRepository.findByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(question));
    given(questionRepository.countByConversationSessionIdAndSkippedTrue(CONVERSATION_ID))
        .willReturn(2);
    given(conversation.getConversationStatus()).willReturn("CONVERSING");

    SkipQuestionResponse response = service.skip(CONVERSATION_ID, request(null));

    assertThat(question.isSkipped()).isTrue();
    assertThat(response.skipped()).isTrue();
    assertThat(response.alreadySkipped()).isFalse();
    assertThat(response.skippedQuestionCount()).isEqualTo(2);
    assertThat(response.conversationStatus()).isEqualTo("CONVERSING");
  }

  @Test
  void returnsSameResultWhenQuestionWasAlreadySkipped() {
    SkippableQuestionMessage question = message("QUESTION", true);
    givenConversingAccess();
    given(questionRepository.findByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(question));
    given(questionRepository.countByConversationSessionIdAndSkippedTrue(CONVERSATION_ID))
        .willReturn(1);

    SkipQuestionResponse response = service.skip(CONVERSATION_ID, request(null));

    assertThat(response.skipped()).isTrue();
    assertThat(response.alreadySkipped()).isTrue();
  }

  @Test
  void rejectsAnswerMessageIdAsQuestion() {
    givenConversingAccess();
    given(questionRepository.findByIdAndConversationSessionId(QUESTION_ID, CONVERSATION_ID))
        .willReturn(Optional.of(message("VOICE_ANSWER", false)));

    assertThatThrownBy(() -> service.skip(CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.QUESTION_MESSAGE_NOT_FOUND));
  }

  @Test
  void rejectsReturnToDrawingWithoutTouchingQuestion() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(authorizationRepository.hasConversationAccess(GUARDIAN_ID, CONVERSATION_ID))
        .willReturn(true);

    assertThatThrownBy(() -> service.skip(CONVERSATION_ID, request(true)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.QUESTION_SKIP_RETURN_TO_DRAWING_UNSUPPORTED));

    verify(conversationRepository, never()).findByIdForUpdate(anyLong());
    verify(questionRepository, never()).findByIdAndConversationSessionId(any(), any());
  }

  @Test
  void rejectsSkipWhenConversationIsNotConversing() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(authorizationRepository.hasConversationAccess(GUARDIAN_ID, CONVERSATION_ID))
        .willReturn(true);
    given(conversationRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.of(conversation));
    given(conversation.isConversing()).willReturn(false);

    assertThatThrownBy(() -> service.skip(CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.CONVERSATION_NOT_CONVERSING));
  }

  @Test
  void hidesExistenceWhenGuardianCannotAccessConversation() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(authorizationRepository.hasConversationAccess(GUARDIAN_ID, CONVERSATION_ID))
        .willReturn(false);

    assertThatThrownBy(() -> service.skip(CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(QuestionSkipErrorCode.CONVERSATION_NOT_FOUND));

    verify(conversationRepository, never()).findByIdForUpdate(anyLong());
  }

  private void givenConversingAccess() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(authorizationRepository.hasConversationAccess(GUARDIAN_ID, CONVERSATION_ID))
        .willReturn(true);
    given(conversationRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.of(conversation));
    given(conversation.isConversing()).willReturn(true);
  }

  private SkipQuestionRequest request(Boolean returnToDrawing) {
    return new SkipQuestionRequest(
        QUESTION_ID, ConversationCompletionReason.CHILD_REQUEST, returnToDrawing);
  }

  private SkippableQuestionMessage message(String messageType, boolean skipped) {
    SkippableQuestionMessage message = BeanUtils.instantiateClass(SkippableQuestionMessage.class);
    ReflectionTestUtils.setField(message, "id", QUESTION_ID);
    ReflectionTestUtils.setField(message, "conversationSessionId", CONVERSATION_ID);
    ReflectionTestUtils.setField(message, "messageType", messageType);
    ReflectionTestUtils.setField(message, "skipped", skipped);
    return message;
  }
}
