package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ErrorCode;
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

/** 아이가 말로 확인한 대화 종료가 칩 종료와 같은 결과를 남기는지 검증한다(S15P11B209-947). */
@ExtendWith(MockitoExtension.class)
class ChildRequestConversationEndServiceTest {

  private static final Instant NOW = Instant.parse("2026-08-05T12:00:00Z");

  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private ConversationSession session;
  @Mock private DrawingSession drawingSession;

  private ChildRequestConversationEndService service;

  @BeforeEach
  void setUp() {
    service =
        new ChildRequestConversationEndService(
            conversationSessionRepository,
            drawingSessionRepository,
            Clock.fixed(NOW, ZoneOffset.UTC));
    lenient().when(session.getDrawingSessionId()).thenReturn(9L);
  }

  @Test
  void completesTheConversationWithChildRequestAndMovesToReflection() {
    givenConversingSession();
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(9L))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.CONVERSING);

    service.endByChildRequest(1L);

    verify(session)
        .complete(
            ConversationCompletionReason.CHILD_REQUEST,
            LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
    verify(drawingSession).enterReflection();
  }

  @Test
  void keepsTheDrawingStageWhenTheConversationStartedWhileDrawing() {
    givenConversingSession();
    given(drawingSessionRepository.findNotDeletedByIdForUpdate(9L))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.getCurrentStage()).willReturn(DrawingStage.DRAWING);

    service.endByChildRequest(1L);

    verify(session)
        .complete(
            ConversationCompletionReason.CHILD_REQUEST,
            LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
    verify(drawingSession, never()).enterReflection();
  }

  @Test
  void leavesTheFirstCompletionUntouchedWhenTheSameConfirmationArrivesTwice() {
    given(conversationSessionRepository.findByIdForUpdate(1L)).willReturn(Optional.of(session));
    given(session.isCompleted()).willReturn(true);

    service.endByChildRequest(1L);

    verify(session, never()).complete(any(), any());
    verifyNoInteractions(drawingSessionRepository);
  }

  @Test
  void rejectsSessionsThatAreNotConversing() {
    given(conversationSessionRepository.findByIdForUpdate(1L)).willReturn(Optional.of(session));
    given(session.isCompleted()).willReturn(false);
    given(session.isConversing()).willReturn(false);

    assertBusinessError(
        () -> service.endByChildRequest(1L), ConversationStartErrorCode.INVALID_STATE_TRANSITION);
    verifyNoInteractions(drawingSessionRepository);
  }

  @Test
  void rejectsUnknownConversations() {
    given(conversationSessionRepository.findByIdForUpdate(404L)).willReturn(Optional.empty());

    assertBusinessError(
        () -> service.endByChildRequest(404L),
        ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND);
  }

  private void givenConversingSession() {
    given(conversationSessionRepository.findByIdForUpdate(1L)).willReturn(Optional.of(session));
    given(session.isCompleted()).willReturn(false);
    given(session.isConversing()).willReturn(true);
  }

  private void assertBusinessError(Runnable action, ErrorCode expected) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception -> assertThat(exception.getErrorCode()).isEqualTo(expected));
  }
}
