package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.domain.DrawingCoordinateSpace;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.analysis.service.DrawingAnalysisActivityContext;
import com.ssafy.b209.analysis.service.DrawingAnalysisActivityContextResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationHistoryOption;
import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationMessageSelectedOption;
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
import com.ssafy.b209.conversation.dto.RecentMessage;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationHistoryOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageSelectedOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageTargetRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
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
import org.springframework.data.domain.Pageable;

/** 283 공개 DTO 변환과 보호자 접근 경계를 검증한다. */
@ExtendWith(MockitoExtension.class)
class ConversationNextQuestionServiceTest {
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationMessageRepository conversationMessageRepository;
  @Mock private ConversationHistoryMessageRepository conversationHistoryMessageRepository;
  @Mock private ConversationHistoryOptionRepository conversationHistoryOptionRepository;

  @Mock
  private ConversationMessageSelectedOptionRepository conversationMessageSelectedOptionRepository;

  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private ConversationMessageTargetRepository conversationMessageTargetRepository;
  @Mock private DrawingSessionRepository drawingSessionDetailRepository;
  @Mock private DrawingAnalysisActivityContextResolver activityContextResolver;
  @Mock private ConversationStartAuthorizationRepository authorizationRepository;
  @Mock private ChildRepository childRepository;
  @Mock private DrawingAnalysisRepository drawingAnalysisRepository;
  @Mock private ConversationQuestionService questionService;
  @Mock private ConversationSession session;
  @Mock private ConversationStartDrawingSession drawingSession;
  @Mock private DrawingSession drawingSessionDetail;
  @Mock private Child child;

  private ConversationNextQuestionService service;

  @BeforeEach
  void setUp() {
    service =
        new ConversationNextQuestionService(
            conversationSessionRepository,
            conversationMessageRepository,
            conversationHistoryMessageRepository,
            conversationHistoryOptionRepository,
            conversationMessageSelectedOptionRepository,
            drawingSessionRepository,
            conversationMessageTargetRepository,
            drawingSessionDetailRepository,
            activityContextResolver,
            authorizationRepository,
            childRepository,
            drawingAnalysisRepository,
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
  void assemblesRecentMessagesInChronologicalOrderPreferringSttText() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    ConversationHistoryMessage olderQuestion =
        historyMessage(101L, "AI", "QUESTION", "무엇을 그렸니?", null);
    ConversationHistoryMessage newerAnswer =
        historyMessage(102L, "CHILD", "VOICE_ANSWER", null, "강아지요");
    given(
            conversationHistoryMessageRepository.findRecentContextMessages(
                org.mockito.ArgumentMatchers.eq(11L),
                org.mockito.ArgumentMatchers.any(Pageable.class)))
        .willReturn(List.of(newerAnswer, olderQuestion));
    given(questionService.generateQuestion(any()))
        .willReturn(new GeneratedQuestion(903L, "강아지는 어떤 색이니?", false, 3, List.of(), null));

    service.generate(
        3L, 11L, new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.VOICE)));

    ArgumentCaptor<GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(GenerateQuestionCommand.class);
    verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().recentMessages())
        .containsExactly(
            new RecentMessage(101L, "AI", "QUESTION", "무엇을 그렸니?"),
            new RecentMessage(102L, "CHILD", "VOICE_ANSWER", "강아지요"));

    ArgumentCaptor<Pageable> pageableCaptor = ArgumentCaptor.forClass(Pageable.class);
    verify(conversationHistoryMessageRepository)
        .findRecentContextMessages(org.mockito.ArgumentMatchers.eq(11L), pageableCaptor.capture());
    assertThat(pageableCaptor.getValue().getPageSize()).isEqualTo(10);
  }

  @Test
  void includesSelectedOptionCodesAndLabelsInRecentMessageContext() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    ConversationHistoryMessage optionAnswer =
        historyMessage(102L, "CHILD", "OPTION_ANSWER", "고양이 같아", null);
    ConversationMessageSelectedOption selectedOption =
        org.mockito.Mockito.mock(ConversationMessageSelectedOption.class);
    ConversationHistoryOption option = org.mockito.Mockito.mock(ConversationHistoryOption.class);
    given(
            conversationHistoryMessageRepository.findRecentContextMessages(
                org.mockito.ArgumentMatchers.eq(11L),
                org.mockito.ArgumentMatchers.any(Pageable.class)))
        .willReturn(List.of(optionAnswer));
    given(
            conversationMessageSelectedOptionRepository
                .findByAnswerMessageIdInOrderByAnswerMessageIdAscSelectionOrderAsc(List.of(102L)))
        .willReturn(List.of(selectedOption));
    given(selectedOption.getAnswerMessageId()).willReturn(102L);
    given(selectedOption.getMessageOptionId()).willReturn(501L);
    given(selectedOption.getLabelSnapshot()).willReturn("음, 아니야");
    given(conversationHistoryOptionRepository.findByIdIn(List.of(501L)))
        .willReturn(List.of(option));
    given(option.getId()).willReturn(501L);
    given(option.getOptionKey()).willReturn("CHIP_NO");
    given(questionService.generateQuestion(any()))
        .willReturn(new GeneratedQuestion(904L, "그럼 무엇처럼 보여?", false, 3, List.of(), null));

    service.generate(
        3L, 11L, new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.EMOJI)));

    ArgumentCaptor<GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(GenerateQuestionCommand.class);
    verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().recentMessages())
        .containsExactly(
            new RecentMessage(
                102L, "CHILD", "OPTION_ANSWER", "음, 아니야 / 고양이 같아", List.of("CHIP_NO")));
  }

  @Test
  void sendsEmptyContextWhenNoRecentMessagesAndKeepsDetectedObjectsEmpty() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    given(
            conversationHistoryMessageRepository.findRecentContextMessages(
                org.mockito.ArgumentMatchers.eq(11L),
                org.mockito.ArgumentMatchers.any(Pageable.class)))
        .willReturn(List.of());
    given(questionService.generateQuestion(any()))
        .willReturn(new GeneratedQuestion(904L, "무엇을 그리고 있니?", false, 1, List.of(), null));

    service.generate(
        3L, 11L, new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.VOICE)));

    ArgumentCaptor<GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(GenerateQuestionCommand.class);
    verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().recentMessages()).isEmpty();
    assertThat(commandCaptor.getValue().detectedObjects()).isEmpty();
  }

  @Test
  void sendsOnlyNormalizedObjectsFromCompletedBasisAnalysis() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    DrawingAnalysis analysis = org.mockito.Mockito.mock(DrawingAnalysis.class);
    DrawingDetectedObject normalized = org.mockito.Mockito.mock(DrawingDetectedObject.class);
    DrawingDetectedObject pixel = org.mockito.Mockito.mock(DrawingDetectedObject.class);
    given(drawingAnalysisRepository.findDetailBySessionIdAndAnalysisId(101L, 700L))
        .willReturn(Optional.of(analysis));
    given(analysis.getState()).willReturn(DrawingAnalysisState.PARTIAL_SUCCESS);
    given(analysis.getDetections()).willReturn(List.of(normalized, pixel));
    given(normalized.getCoordinateSpace()).willReturn(DrawingCoordinateSpace.NORMALIZED);
    given(normalized.getLabel()).willReturn("HOUSE");
    given(normalized.getObjectName()).willReturn("집");
    given(normalized.getConfidence()).willReturn(new java.math.BigDecimal("0.93"));
    given(normalized.getX()).willReturn(new java.math.BigDecimal("0.1"));
    given(normalized.getY()).willReturn(new java.math.BigDecimal("0.2"));
    given(normalized.getWidth()).willReturn(new java.math.BigDecimal("0.3"));
    given(normalized.getHeight()).willReturn(new java.math.BigDecimal("0.4"));
    given(pixel.getCoordinateSpace()).willReturn(DrawingCoordinateSpace.PIXEL);
    given(questionService.generateQuestion(any()))
        .willReturn(new GeneratedQuestion(905L, "집에는 누가 있니?", false, 1, List.of(), null));

    service.generate(3L, 11L, request());

    ArgumentCaptor<GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(GenerateQuestionCommand.class);
    verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().detectedObjects())
        .containsExactly(
            new DetectedObject("HOUSE", "집", 0.93, new BoundingBox(0.1, 0.2, 0.3, 0.4)));
  }

  // ── HTP 주제·기질문 대상 조립 — S15P11B209-712 ─────────────────────────
  @Test
  void resolvesActivityTypeAndSubjectFromDrawingSession() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    given(questionService.generateQuestion(any()))
        .willReturn(new GeneratedQuestion(910L, "집에는 누가 사니?", false, 1, List.of(), null));

    service.generate(
        3L, 11L, new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.VOICE)));

    ArgumentCaptor<GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(GenerateQuestionCommand.class);
    verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().activityType()).isEqualTo("HTP");
    assertThat(commandCaptor.getValue().drawingSubject()).isEqualTo("HOUSE");
  }

  @Test
  void fallsBackToNullSubjectWhenResolverRejectsSession() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    given(activityContextResolver.resolve(drawingSessionDetail))
        .willThrow(new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED));
    given(questionService.generateQuestion(any()))
        .willReturn(new GeneratedQuestion(911L, "무엇을 그리고 있니?", false, 1, List.of(), null));

    service.generate(
        3L, 11L, new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.VOICE)));

    // 주제 확정 실패는 대화를 끊지 않는다 — 두 값은 null로 두고 계속 진행한다.
    ArgumentCaptor<GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(GenerateQuestionCommand.class);
    verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().activityType()).isNull();
    assertThat(commandCaptor.getValue().drawingSubject()).isNull();
  }

  @Test
  void collectsAskedObjectCodesFromWholeConversation() {
    stubAuthorizedConversation(false, true, true);
    stubChildContext();
    given(conversationMessageTargetRepository.findAskedObjectCodes(11L))
        .willReturn(List.of("TREE", "SUN"));
    given(questionService.generateQuestion(any()))
        .willReturn(new GeneratedQuestion(912L, "해는 어디에 있니?", false, 2, List.of(), null));

    service.generate(
        3L, 11L, new NextQuestionRequest(700L, null, List.of(PreferredResponseMode.VOICE)));

    ArgumentCaptor<GenerateQuestionCommand> commandCaptor =
        ArgumentCaptor.forClass(GenerateQuestionCommand.class);
    verify(questionService).generateQuestion(commandCaptor.capture());
    assertThat(commandCaptor.getValue().askedObjectCodes()).containsExactly("TREE", "SUN");
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
    lenient()
        .when(drawingSessionDetailRepository.findDetailById(101L))
        .thenReturn(Optional.of(drawingSessionDetail));
    lenient()
        .when(activityContextResolver.resolve(drawingSessionDetail))
        .thenReturn(
            new DrawingAnalysisActivityContext(
                DrawingAnalysisActivityType.HTP, DrawingAnalysisSubject.HOUSE));
    lenient()
        .when(conversationMessageTargetRepository.findAskedObjectCodes(11L))
        .thenReturn(List.of());
  }

  private ConversationHistoryMessage historyMessage(
      Long id, String senderType, String messageType, String rawText, String sttText) {
    ConversationHistoryMessage message = org.mockito.Mockito.mock(ConversationHistoryMessage.class);
    lenient().when(message.getId()).thenReturn(id);
    lenient().when(message.getSenderType()).thenReturn(senderType);
    lenient().when(message.getMessageType()).thenReturn(messageType);
    lenient().when(message.getRawText()).thenReturn(rawText);
    lenient().when(message.getSttText()).thenReturn(sttText);
    lenient().when(message.isOptionAnswer()).thenReturn("OPTION_ANSWER".equals(messageType));
    return message;
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
