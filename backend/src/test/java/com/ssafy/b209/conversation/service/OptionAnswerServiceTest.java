package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.domain.ConversationMessageOption;
import com.ssafy.b209.conversation.domain.ConversationMessageSelectedOption;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.domain.OptionAnswerMessage;
import com.ssafy.b209.conversation.dto.OptionAnswerRequest;
import com.ssafy.b209.conversation.dto.OptionAnswerResponse;
import com.ssafy.b209.conversation.dto.SelectedOptionCommand;
import com.ssafy.b209.conversation.exception.OptionAnswerErrorCode;
import com.ssafy.b209.conversation.repository.ConversationMessageOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageSelectedOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.OptionAnswerMessageRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

/** 선택형 답변 저장의 검증 경계·저장 값·선택 순서·오류 매핑을 검증한다. */
@ExtendWith(MockitoExtension.class)
class OptionAnswerServiceTest {
  private static final long GUARDIAN_ID = 10L;
  private static final long CONVERSATION_ID = 20L;
  private static final long DRAWING_SESSION_ID = 30L;
  private static final long CHILD_ID = 40L;
  private static final long QUESTION_ID = 50L;
  private static final long ANSWER_ID = 60L;
  private static final long OPTION_ROW_ID = 70L;

  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private VoiceAnswerAuthorizationRepository authorizationRepository;
  @Mock private OptionAnswerMessageRepository messageRepository;
  @Mock private ConversationMessageOptionRepository optionRepository;
  @Mock private ConversationMessageSelectedOptionRepository selectedOptionRepository;
  @Mock private ConversationSession session;
  @Mock private ConversationStartDrawingSession drawingSession;
  @Mock private ConversationMessageOption option;
  @Mock private OptionAnswerMessage savedMessage;
  @Mock private ConversationEventRecorder eventRecorder;

  private OptionAnswerService service;

  @BeforeEach
  void setUp() {
    service =
        new OptionAnswerService(
            conversationSessionRepository,
            drawingSessionRepository,
            authorizationRepository,
            messageRepository,
            optionRepository,
            selectedOptionRepository,
            eventRecorder,
            new ObjectMapper(),
            Clock.fixed(Instant.parse("2026-07-23T00:00:00Z"), ZoneOffset.UTC));
  }

  @Test
  void persistsOptionAnswerWithParentAndSelectionOrder() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .willReturn(false);
    givenHappyOption();
    given(option.getId()).willReturn(OPTION_ROW_ID);
    given(optionRepository.findByConversationMessageId(QUESTION_ID)).willReturn(List.of(option));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(messageRepository.saveAndFlush(any(OptionAnswerMessage.class))).willReturn(savedMessage);
    given(savedMessage.getId()).willReturn(ANSWER_ID);
    given(savedMessage.getParentMessageId()).willReturn(QUESTION_ID);
    given(savedMessage.getMessageSequence()).willReturn(5);
    given(savedMessage.getSenderType()).willReturn("CHILD");
    given(savedMessage.getCreatedAt()).willReturn(LocalDateTime.parse("2026-07-23T00:00:00"));

    OptionAnswerResponse response = service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null));

    ArgumentCaptor<OptionAnswerMessage> messageCaptor =
        ArgumentCaptor.forClass(OptionAnswerMessage.class);
    verify(messageRepository).saveAndFlush(messageCaptor.capture());
    OptionAnswerMessage message = messageCaptor.getValue();
    assertThat(message.getConversationSessionId()).isEqualTo(CONVERSATION_ID);
    assertThat(message.getParentMessageId()).isEqualTo(QUESTION_ID);
    assertThat(message.getMessageSequence()).isEqualTo(5);
    assertThat(message.getSenderType()).isEqualTo("CHILD");
    assertThat(message.getMessageType()).isEqualTo("OPTION_ANSWER");
    assertThat(message.getRawText()).isNull();

    ArgumentCaptor<List<ConversationMessageSelectedOption>> selectionCaptor =
        ArgumentCaptor.forClass(List.class);
    verify(selectedOptionRepository).saveAll(selectionCaptor.capture());
    List<ConversationMessageSelectedOption> selections = selectionCaptor.getValue();
    assertThat(selections).hasSize(1);
    ConversationMessageSelectedOption selection = selections.get(0);
    assertThat(selection.getAnswerMessageId()).isEqualTo(ANSWER_ID);
    assertThat(selection.getQuestionMessageId()).isEqualTo(QUESTION_ID);
    assertThat(selection.getMessageOptionId()).isEqualTo(OPTION_ROW_ID);
    assertThat(selection.getLabelSnapshot()).isEqualTo("기뻐요");
    assertThat(selection.getSelectionOrder()).isEqualTo((short) 0);

    assertThat(response.messageId()).isEqualTo(ANSWER_ID);
    assertThat(response.conversationId()).isEqualTo(CONVERSATION_ID);
    assertThat(response.parentMessageId()).isEqualTo(QUESTION_ID);
    assertThat(response.sequence()).isEqualTo(5);
    assertThat(response.senderType()).isEqualTo("CHILD");
    assertThat(response.messageType()).isEqualTo("ANSWER_OPTION");
    assertThat(response.directText()).isNull();
    assertThat(response.selectedOptions()).hasSize(1);
  }

  @Test
  void storesDirectTextWhenProvided() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .willReturn(false);
    givenHappyOption();
    given(option.getId()).willReturn(OPTION_ROW_ID);
    given(optionRepository.findByConversationMessageId(QUESTION_ID)).willReturn(List.of(option));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(0);
    given(messageRepository.saveAndFlush(any(OptionAnswerMessage.class))).willReturn(savedMessage);
    given(savedMessage.getId()).willReturn(ANSWER_ID);
    given(savedMessage.getParentMessageId()).willReturn(QUESTION_ID);
    given(savedMessage.getMessageSequence()).willReturn(1);
    given(savedMessage.getSenderType()).willReturn("CHILD");
    given(savedMessage.getCreatedAt()).willReturn(LocalDateTime.parse("2026-07-23T00:00:00"));

    OptionAnswerResponse response =
        service.submit(GUARDIAN_ID, CONVERSATION_ID, request("우리 강아지예요"));

    ArgumentCaptor<OptionAnswerMessage> messageCaptor =
        ArgumentCaptor.forClass(OptionAnswerMessage.class);
    verify(messageRepository).saveAndFlush(messageCaptor.capture());
    assertThat(messageCaptor.getValue().getRawText()).isEqualTo("우리 강아지예요");
    assertThat(response.directText()).isEqualTo("우리 강아지예요");
  }

  @Test
  void rejectsMissingConversation() {
    given(conversationSessionRepository.findByIdForUpdate(CONVERSATION_ID))
        .willReturn(Optional.empty());

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.CONVERSATION_NOT_FOUND));
    verify(messageRepository, never()).saveAndFlush(any());
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

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.CONVERSATION_ACCESS_DENIED));
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

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.CONSENT_REQUIRED));
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

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.CONVERSATION_ALREADY_COMPLETED));
  }

  @Test
  void rejectsQuestionThatIsNotInConversation() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(false);

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.QUESTION_MESSAGE_NOT_FOUND));
    verify(messageRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsWhenQuestionAlreadyAnswered() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID)).willReturn(true);

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.ANSWER_ALREADY_SUBMITTED));
    verify(messageRepository, never()).saveAndFlush(any());
  }

  /**
   * 아이가 고른 답이 아직 글로 바뀌지 않은 음성 답변을 밀어낸다 (P0-1).
   *
   * <p>자동 녹음이 먼저 올라가 있고 그 STT가 아직 {@code PENDING}인 사이에 아이가 보기를 누르면, 예전에는 409로 거절됐다. 아이가 <b>직접
   * 고른</b> 답이 자동으로 켜진 녹음에 밀린 셈이다.
   *
   * <p>밀어낸 음성 답변은 지우지 않고 {@code superseded_at}으로 표시한다 — 아이가 실제로 낸 소리이고, 누가 대신했는지도 남아야 한다.
   */
  @Test
  void supersedesPendingVoiceAnswerWhenChildPicksOption() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID)).willReturn(true);
    OptionAnswerMessage staleVoiceAnswer = org.mockito.Mockito.mock(OptionAnswerMessage.class);
    given(messageRepository.findSupersedableVoiceAnswers(CONVERSATION_ID, QUESTION_ID))
        .willReturn(List.of(staleVoiceAnswer));
    givenHappyOption();
    given(option.getId()).willReturn(OPTION_ROW_ID);
    given(optionRepository.findByConversationMessageId(QUESTION_ID)).willReturn(List.of(option));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(messageRepository.saveAndFlush(any(OptionAnswerMessage.class))).willReturn(savedMessage);
    given(savedMessage.getId()).willReturn(ANSWER_ID);
    given(savedMessage.getParentMessageId()).willReturn(QUESTION_ID);
    given(savedMessage.getMessageSequence()).willReturn(5);
    given(savedMessage.getSenderType()).willReturn("CHILD");
    given(savedMessage.getCreatedAt()).willReturn(LocalDateTime.parse("2026-07-23T00:00:00"));

    OptionAnswerResponse response = service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null));

    assertThat(response.messageId()).isEqualTo(ANSWER_ID);
    verify(staleVoiceAnswer).supersede(eq(ANSWER_ID), any(LocalDateTime.class));
  }

  /** 이미 확정된 답은 어떤 경우에도 덮어쓰지 않는다 (P0-1). */
  @Test
  void rejectsWhenAnsweredAndNothingIsSupersedable() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID)).willReturn(true);
    given(messageRepository.findSupersedableVoiceAnswers(CONVERSATION_ID, QUESTION_ID))
        .willReturn(List.of());

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.ANSWER_ALREADY_SUBMITTED));
    verify(messageRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsOptionNotBelongingToQuestion() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .willReturn(false);
    given(optionRepository.findByConversationMessageId(QUESTION_ID)).willReturn(List.of());

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.OPTION_NOT_ALLOWED));
    verify(messageRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsOptionSnapshotMismatch() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .willReturn(false);
    given(option.getOptionKey()).willReturn("happy");
    given(option.getOptionType()).willReturn("EMOTION");
    given(option.getOptionValue()).willReturn("HAPPY");
    given(option.getLabel()).willReturn("아주 기뻐요");
    given(optionRepository.findByConversationMessageId(QUESTION_ID)).willReturn(List.of(option));

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.OPTION_NOT_ALLOWED));
    verify(messageRepository, never()).saveAndFlush(any());
  }

  @Test
  void rejectsDuplicateOptionInRequest() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .willReturn(false);
    givenHappyOption();
    given(optionRepository.findByConversationMessageId(QUESTION_ID)).willReturn(List.of(option));
    OptionAnswerRequest duplicated =
        new OptionAnswerRequest(
            QUESTION_ID,
            List.of(
                new SelectedOptionCommand("happy", "EMOTION", "HAPPY", "기뻐요"),
                new SelectedOptionCommand("happy", "EMOTION", "HAPPY", "기뻐요")),
            null);

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, duplicated))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.OPTION_NOT_ALLOWED));
    verify(messageRepository, never()).saveAndFlush(any());
  }

  @Test
  void mapsStorageConflictToBusinessException() {
    givenAuthorizedConversingSession();
    given(messageRepository.existsQuestion(QUESTION_ID, CONVERSATION_ID)).willReturn(true);
    given(messageRepository.existsAnswerForQuestion(CONVERSATION_ID, QUESTION_ID))
        .willReturn(false);
    givenHappyOption();
    given(optionRepository.findByConversationMessageId(QUESTION_ID)).willReturn(List.of(option));
    given(messageRepository.findMaxMessageSequenceByConversationSessionId(CONVERSATION_ID))
        .willReturn(4);
    given(messageRepository.saveAndFlush(any(OptionAnswerMessage.class)))
        .willThrow(new DataIntegrityViolationException("sequence conflict"));

    assertThatThrownBy(() -> service.submit(GUARDIAN_ID, CONVERSATION_ID, request(null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(OptionAnswerErrorCode.OPTION_ANSWER_STORAGE_CONFLICT));
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

  private void givenHappyOption() {
    given(option.getOptionKey()).willReturn("happy");
    given(option.getOptionType()).willReturn("EMOTION");
    given(option.getOptionValue()).willReturn("HAPPY");
    given(option.getLabel()).willReturn("기뻐요");
  }

  private OptionAnswerRequest request(String directText) {
    return new OptionAnswerRequest(
        QUESTION_ID,
        List.of(new SelectedOptionCommand("happy", "EMOTION", "HAPPY", "기뻐요")),
        directText);
  }
}
