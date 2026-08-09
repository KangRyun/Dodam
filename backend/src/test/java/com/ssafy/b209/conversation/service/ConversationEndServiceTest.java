package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.dto.EndConversationRequest;
import com.ssafy.b209.conversation.dto.EndConversationResponse;
import com.ssafy.b209.conversation.exception.ConversationEndErrorCode;
import com.ssafy.b209.conversation.repository.ConversationEndAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class ConversationEndServiceTest {

  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-24T07:30:00Z"), ZoneOffset.UTC);

  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private ConversationEndAuthorizationRepository authorizationRepository;
  @Mock private ConversationSessionRepository conversationRepository;
  @Mock private DrawingSessionRepository drawingRepository;
  @Mock private ConversationMessageRepository messageRepository;
  @Mock private DrawingSession drawingSession;
  @Mock private ConversationEventRecorder eventRecorder;

  private ConversationEndService service;

  @BeforeEach
  void setUp() {
    service =
        new ConversationEndService(
            currentUserResolver,
            authorizationRepository,
            conversationRepository,
            drawingRepository,
            messageRepository,
            eventRecorder,
            CLOCK);
  }

  @Test
  void completesConversationAndMovesDrawingSessionToReflection() {
    ConversationSession conversation = conversation();
    ConversationMessage latestQuestion = question(803L);
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
    given(drawingRepository.findNotDeletedByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.CONVERSING);
    given(
            messageRepository
                .findFirstByConversationSessionIdAndMessageTypeOrderByMessageSequenceDesc(
                    20L, "QUESTION"))
        .willReturn(Optional.of(latestQuestion));

    EndConversationResponse response =
        service.end(
            20L, new EndConversationRequest(ConversationCompletionReason.GUARDIAN_REQUEST, 803L));

    assertThat(response.conversationId()).isEqualTo(20L);
    assertThat(response.completed()).isTrue();
    assertThat(response.completionReason())
        .isEqualTo(ConversationCompletionReason.GUARDIAN_REQUEST);
    assertThat(response.completedAt()).isEqualTo(LocalDateTime.of(2026, 7, 24, 7, 30));
    assertThat(response.nextStage()).isEqualTo(DrawingStage.REFLECTION);
    assertThat(conversation.isCompleted()).isTrue();
    verify(drawingSession).enterReflection();
  }

  @Test
  void completesConversationWithoutLeavingDrawingStage() {
    ConversationSession conversation = conversation();
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
    given(drawingRepository.findNotDeletedByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.DRAWING);

    EndConversationResponse response =
        service.end(
            20L, new EndConversationRequest(ConversationCompletionReason.CHILD_REQUEST, null));

    assertThat(response.completed()).isTrue();
    assertThat(response.nextStage()).isEqualTo(DrawingStage.DRAWING);
    verify(drawingSession, never()).enterReflection();
  }

  @Test
  void completesConversationWithoutInterruptingFinalAnalysis() {
    ConversationSession conversation = conversation();
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
    given(drawingRepository.findNotDeletedByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.ANALYZING);

    EndConversationResponse response =
        service.end(
            20L, new EndConversationRequest(ConversationCompletionReason.CHILD_REQUEST, null));

    assertThat(response.completed()).isTrue();
    assertThat(response.nextStage()).isEqualTo(DrawingStage.ANALYZING);
    verify(drawingSession, never()).enterReflection();
  }

  @Test
  void hidesExistenceWhenGuardianCannotAccessConversation() {
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(false);

    assertThatThrownBy(
            () ->
                service.end(
                    20L,
                    new EndConversationRequest(
                        ConversationCompletionReason.GUARDIAN_REQUEST, null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationEndErrorCode.CONVERSATION_NOT_FOUND));

    verify(conversationRepository, never()).findByIdForUpdate(20L);
  }

  @Test
  void hidesExistenceWhenConversationDoesNotExist() {
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.empty());

    assertThatThrownBy(
            () ->
                service.end(
                    20L,
                    new EndConversationRequest(
                        ConversationCompletionReason.GUARDIAN_REQUEST, null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationEndErrorCode.CONVERSATION_NOT_FOUND));
  }

  @Test
  void rejectsStaleLastQuestionSnapshot() {
    ConversationSession conversation = conversation();
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
    given(drawingRepository.findNotDeletedByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(
            messageRepository
                .findFirstByConversationSessionIdAndMessageTypeOrderByMessageSequenceDesc(
                    20L, "QUESTION"))
        .willReturn(Optional.of(question(804L)));

    assertThatThrownBy(
            () ->
                service.end(
                    20L,
                    new EndConversationRequest(ConversationCompletionReason.CHILD_REQUEST, 803L)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationEndErrorCode.CONVERSATION_LAST_QUESTION_MISMATCH));

    assertThat(conversation.isConversing()).isTrue();
    verify(drawingSession, never()).enterReflection();
  }

  @Test
  void allowsEndingWithoutLastQuestionSnapshot() {
    ConversationSession conversation = conversation();
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
    given(drawingRepository.findNotDeletedByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));

    EndConversationResponse response =
        service.end(
            20L, new EndConversationRequest(ConversationCompletionReason.NO_MORE_QUESTION, null));

    assertThat(response.completed()).isTrue();
    verify(messageRepository, never())
        .findFirstByConversationSessionIdAndMessageTypeOrderByMessageSequenceDesc(20L, "QUESTION");
  }

  @Test
  void rejectsLastQuestionSnapshotWhenNoQuestionExists() {
    ConversationSession conversation = conversation();
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
    given(drawingRepository.findNotDeletedByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(
            messageRepository
                .findFirstByConversationSessionIdAndMessageTypeOrderByMessageSequenceDesc(
                    20L, "QUESTION"))
        .willReturn(Optional.empty());

    assertThatThrownBy(
            () ->
                service.end(
                    20L,
                    new EndConversationRequest(ConversationCompletionReason.CHILD_REQUEST, 803L)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationEndErrorCode.CONVERSATION_LAST_QUESTION_MISMATCH));

    verify(drawingSession, never()).enterReflection();
  }

  @Test
  void returnsStoredCompletionWithoutChangingIt() {
    ConversationSession conversation = conversation();
    conversation.complete(
        ConversationCompletionReason.QUESTION_LIMIT_REACHED, LocalDateTime.of(2026, 7, 24, 7, 20));
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
    given(drawingRepository.findNotDeletedByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.REFLECTION);

    EndConversationResponse response =
        service.end(
            20L, new EndConversationRequest(ConversationCompletionReason.GUARDIAN_REQUEST, 803L));

    assertThat(response.completionReason())
        .isEqualTo(ConversationCompletionReason.QUESTION_LIMIT_REACHED);
    assertThat(response.completedAt()).isEqualTo(LocalDateTime.of(2026, 7, 24, 7, 20));
    assertThat(response.nextStage()).isEqualTo(DrawingStage.REFLECTION);
    verify(drawingSession, never()).enterReflection();
  }

  @Test
  void rejectsConversationThatIsNoLongerConversing() {
    ConversationSession conversation = conversation();
    ReflectionTestUtils.setField(conversation, "conversationStatus", "FAILED");
    given(currentUserResolver.requireUserId()).willReturn(7L);
    given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
    given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
    given(drawingRepository.findNotDeletedByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));

    assertThatThrownBy(
            () ->
                service.end(
                    20L,
                    new EndConversationRequest(
                        ConversationCompletionReason.GUARDIAN_REQUEST, null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationEndErrorCode.CONVERSATION_NOT_CONVERSING));

    verify(drawingSession, never()).enterReflection();
  }

  private ConversationSession conversation() {
    ConversationSession conversation =
        ConversationSession.start(100L, "LOW", 5, LocalDateTime.of(2026, 7, 24, 7, 0));
    ReflectionTestUtils.setField(conversation, "id", 20L);
    return conversation;
  }

  private ConversationMessage question(Long id) {
    ConversationMessage question = ConversationMessage.aiQuestion(20L, null, 1, "무엇을 그렸니?");
    ReflectionTestUtils.setField(question, "id", id);
    return question;
  }
}
