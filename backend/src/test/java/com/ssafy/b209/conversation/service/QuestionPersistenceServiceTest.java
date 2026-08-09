package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.conversation.config.ConversationQuestionLimitProperties;
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
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
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
  @Mock private DrawingSessionRepository drawingSessionRepository;

  private static final ConversationQuestionLimitProperties QUESTION_LIMITS =
      new ConversationQuestionLimitProperties(5, 5);

  private QuestionPersistenceService service;
  private ConversationSession session;
  private DrawingSession drawingSession;

  @BeforeEach
  void setUp() {
    service =
        new QuestionPersistenceService(
            conversationSessionRepository,
            conversationMessageRepository,
            conversationMessageOptionRepository,
            conversationMessageTargetRepository,
            drawingSessionRepository,
            QUESTION_LIMITS);
    session = mock(ConversationSession.class);
    // 완료 세션 경로는 isConversing 을 타지 않으므로 lenient 로 둔다.
    lenient().when(session.isConversing()).thenReturn(true);
    lenient().when(session.isCompleted()).thenReturn(false);
    lenient().when(session.canAskQuestion()).thenReturn(true);
    given(conversationSessionRepository.findByIdForUpdate(1L)).willReturn(Optional.of(session));
    // 재개 경로만 그림 활동을 조회한다 — 일반 저장 경로에서는 아무도 부르지 않는다.
    lenient().when(session.getDrawingSessionId()).thenReturn(101L);
    drawingSession = mock(DrawingSession.class);
  }

  /** 재개 판정이 최신 활동 단계를 읽도록 그림 활동을 열린 단계로 세운다. */
  private void stubDrawingActivity(boolean open) {
    given(drawingSessionRepository.findNotDeletedById(101L))
        .willReturn(Optional.of(drawingSession));
    given(drawingSession.canReopenConversation()).willReturn(open);
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
            "안전한 질문", List.of(new QuestionOption("A", "선택지")), null, null, false, null, false));

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

    service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, 44L, false));

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
        () ->
            service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, 44L, false)),
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

    service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, null, false));

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
        () ->
            service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, 44L, false)),
        ConversationErrorCode.QUESTION_MESSAGE_NOT_FOUND);

    verify(conversationMessageRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsSaveAfterConcurrentRequestConsumesLastQuestion() {
    given(session.canAskQuestion()).willReturn(false);

    assertBusinessError(
        () ->
            service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, null, false)),
        ConversationErrorCode.QUESTION_LIMIT_REACHED);

    verify(conversationMessageRepository, never())
        .findMaxMessageSequenceByConversationSessionId(any());
    verify(conversationMessageRepository, never()).saveAndFlush(any());
  }

  // ── 그림일기 대화 재개 — 상태를 바꾸는 유일한 지점 ────────────────────────
  @Test
  void reopensLimitReachedConversationInsideTheLockThenSavesTheQuestion() {
    // 그림일기는 대화가 끝난 뒤에도 캔버스가 바뀐다. 그림 한 장에 대화 세션은 하나뿐이라
    //   새 세션을 여는 대신 끝난 세션을 다시 연다. 재개는 상한을 올리는 상태 변경이므로
    //   비관 잠금을 쥔 여기에서만 일어나야 한다 — 그 호출을 여기서 못박는다.
    given(session.isCompleted()).willReturn(true);
    given(session.isReopenEligible(ConversationQuestionLimitProperties.ABSOLUTE_MAX))
        .willReturn(true);
    stubDrawingActivity(true);
    given(conversationMessageRepository.findMaxMessageSequenceByConversationSessionId(1L))
        .willReturn(5);
    given(conversationMessageRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationMessage message = invocation.getArgument(0);
              ReflectionTestUtils.setField(message, "id", 41L);
              return message;
            });

    service.save(1L, reopenableCandidate());

    verify(conversationSessionRepository).findByIdForUpdate(1L);
    verify(session).reopen(5, ConversationQuestionLimitProperties.ABSOLUTE_MAX);
    verify(conversationMessageRepository).saveAndFlush(any());
    verify(session).increaseQuestionCount();
  }

  @Test
  void rejectsReopenWhenTheDrawingActivityAlreadyMovedPastConversation() {
    // ⚠️ 이번 변경이 연 구멍을 막는 자리다. 앞단은 AI 호출 <b>전</b>의 단계를 보고 통과시키는데,
    //   호출이 도는 몇 초 사이에 아이가 그림을 끝내고 감정 회고·리포트·완료로 넘어갈 수 있다.
    //   그 뒤 도착한 요청이 대화를 되살리면 이미 만들어진 리포트에 없는 말이 완료된 활동에 붙는다.
    //   그래서 잠금 안에서 최신 단계를 다시 읽고, 열린 단계가 아니면 기존과 같은 409로 막는다.
    given(session.isCompleted()).willReturn(true);
    given(session.isReopenEligible(ConversationQuestionLimitProperties.ABSOLUTE_MAX))
        .willReturn(true);
    stubDrawingActivity(false);

    assertBusinessError(
        () -> service.save(1L, reopenableCandidate()),
        ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);

    verify(session, never()).reopen(anyInt(), anyInt());
    verify(conversationMessageRepository, never()).saveAndFlush(any());
    verify(session, never()).increaseQuestionCount();
  }

  @Test
  void rejectsReopenWhenTheDrawingActivityIsGone() {
    // 조회 자체가 비면 열지 않는다 — 재개는 이미 닫힌 것을 여는 동작이라 모르면 닫아 둔다.
    given(session.isCompleted()).willReturn(true);
    given(session.isReopenEligible(ConversationQuestionLimitProperties.ABSOLUTE_MAX))
        .willReturn(true);
    given(drawingSessionRepository.findNotDeletedById(101L)).willReturn(Optional.empty());

    assertBusinessError(
        () -> service.save(1L, reopenableCandidate()),
        ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);

    verify(session, never()).reopen(anyInt(), anyInt());
    verify(conversationMessageRepository, never()).saveAndFlush(any());
  }

  @Test
  void doesNotLookUpTheDrawingActivityForAnOngoingConversation() {
    // 단계 가드는 재개 경로에만 걸린다. 진행 중 대화의 일반 질문 저장은 잠금 안에서 조회를 하나도
    //   더 하지 않으며, 활동 단계와 무관하게 지금까지와 똑같이 저장된다.
    given(conversationMessageRepository.findMaxMessageSequenceByConversationSessionId(1L))
        .willReturn(2);
    given(conversationMessageRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationMessage message = invocation.getArgument(0);
              ReflectionTestUtils.setField(message, "id", 42L);
              return message;
            });

    service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, null, false));

    verify(drawingSessionRepository, never()).findNotDeletedById(any());
    verify(conversationMessageRepository).saveAndFlush(any());
    verify(session).increaseQuestionCount();
  }

  @Test
  void rejectsCompletedConversationWhoseActivityMayNotReopen() {
    // 그림일기가 아닌 활동(HTP)이다. 상위 흐름이 활동 유형을 이미 확정해 값으로 내려보내므로,
    //   잠금 안에서 활동 유형을 다시 조회하지 않고 이 값만 본다. 세션 상태는 보지도 않는다.
    given(session.isCompleted()).willReturn(true);

    assertBusinessError(
        () ->
            service.save(1L, new QuestionCandidate("안전한 질문", null, null, null, false, null, false)),
        ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);

    verify(session, never()).isReopenEligible(anyInt());
    verify(session, never()).reopen(anyInt(), anyInt());
    // 활동 유형에서 이미 걸렸으므로 활동 단계는 조회조차 하지 않는다(단축 평가).
    verify(drawingSessionRepository, never()).findNotDeletedById(any());
    verify(conversationMessageRepository, never()).saveAndFlush(any());
    verify(session, never()).increaseQuestionCount();
  }

  @Test
  void rejectsCompletedConversationThatIsNotReopenEligible() {
    // 그림일기지만 아이·보호자가 직접 끝냈거나 이미 절대 상한(10)까지 올라간 대화다. 기존과 같은
    //   409를 유지해야 FE가 "재개 불가"를 구분할 수 있다.
    given(session.isCompleted()).willReturn(true);
    given(session.isReopenEligible(ConversationQuestionLimitProperties.ABSOLUTE_MAX))
        .willReturn(false);

    assertBusinessError(
        () -> service.save(1L, reopenableCandidate()),
        ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);

    verify(session, never()).reopen(anyInt(), anyInt());
    verify(conversationMessageRepository, never()).saveAndFlush(any());
    verify(session, never()).increaseQuestionCount();
  }

  /** 재개가 허용된 활동(그림일기)에서 올라온 질문 후보. */
  private QuestionCandidate reopenableCandidate() {
    return new QuestionCandidate("안전한 질문", null, null, null, false, null, true);
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
            false,
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
