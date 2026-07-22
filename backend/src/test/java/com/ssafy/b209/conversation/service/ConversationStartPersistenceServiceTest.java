package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartChildProfile;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.StartConversationRequest;
import com.ssafy.b209.conversation.exception.ActiveConversationExistsException;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationStartChildProfileRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.lang.reflect.Constructor;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class ConversationStartPersistenceServiceTest {
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private ConversationStartChildProfileRepository childProfileRepository;
  @Mock private ConversationStartAuthorizationRepository authorizationRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;

  private ConversationStartPersistenceService service;

  @BeforeEach
  void setUp() {
    service =
        new ConversationStartPersistenceService(
            drawingSessionRepository,
            childProfileRepository,
            authorizationRepository,
            conversationSessionRepository,
            Clock.fixed(Instant.parse("2026-07-21T02:30:00Z"), ZoneOffset.UTC));
  }

  @Test
  void createsConversationAndMovesDrawingStage() throws Exception {
    ConversationStartDrawingSession drawingSession = drawingSession();
    ConversationStartChildProfile child = child("LOWER_ELEMENTARY");
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(1L)).willReturn(true);
    given(conversationSessionRepository.findByDrawingSessionId(100L)).willReturn(Optional.empty());
    given(childProfileRepository.findById(1L)).willReturn(Optional.of(child));
    given(conversationSessionRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", 800L);
              return session;
            });

    var response = service.create(9L, 100L, new StartConversationRequest(700L, 5));

    assertThat(response.conversationId()).isEqualTo(800L);
    assertThat(response.difficulty()).isEqualTo("LOWER_ELEMENTARY");
    assertThat(response.questionCount()).isZero();
    assertThat(response.nextAction()).isEqualTo("REQUEST_NEXT_QUESTION");
    verify(conversationSessionRepository).saveAndFlush(any(ConversationSession.class));
  }

  @Test
  void rejectsGuardianWithoutChildRelation() throws Exception {
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession()));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(false);

    assertThatThrownBy(() -> service.create(9L, 100L, null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.RESOURCE_OWNERSHIP_DENIED));
  }

  @Test
  void returnsExistingConversationIdWhenConversationAlreadyExists() throws Exception {
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession()));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(1L)).willReturn(true);
    given(conversationSessionRepository.findByDrawingSessionId(100L))
        .willReturn(Optional.of(existingConversation(800L)));

    assertThatThrownBy(() -> service.create(9L, 100L, null))
        .isInstanceOfSatisfying(
            ActiveConversationExistsException.class,
            exception -> {
              assertThat(exception.getErrorCode())
                  .isEqualTo(ConversationStartErrorCode.ACTIVE_CONVERSATION_EXISTS);
              assertThat(exception.getConversationId()).isEqualTo(800L);
            });
  }

  private ConversationStartDrawingSession drawingSession() throws Exception {
    ConversationStartDrawingSession session = instantiate(ConversationStartDrawingSession.class);
    ReflectionTestUtils.setField(session, "id", 100L);
    ReflectionTestUtils.setField(session, "childId", 1L);
    ReflectionTestUtils.setField(
        session, "sessionStatus", com.ssafy.b209.drawing.domain.DrawingSessionStatus.IN_PROGRESS);
    ReflectionTestUtils.setField(
        session, "currentStage", com.ssafy.b209.drawing.domain.DrawingStage.ANALYZING);
    return session;
  }

  private ConversationStartChildProfile child(String difficulty) throws Exception {
    ConversationStartChildProfile child = instantiate(ConversationStartChildProfile.class);
    ReflectionTestUtils.setField(child, "id", 1L);
    ReflectionTestUtils.setField(
        child, "questionDifficulty", QuestionDifficulty.valueOf(difficulty));
    return child;
  }

  private ConversationSession existingConversation(Long id) throws Exception {
    ConversationSession session = instantiate(ConversationSession.class);
    ReflectionTestUtils.setField(session, "id", id);
    return session;
  }

  private <T> T instantiate(Class<T> type) throws Exception {
    Constructor<T> constructor = type.getDeclaredConstructor();
    constructor.setAccessible(true);
    return constructor.newInstance();
  }
}
