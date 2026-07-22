package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.conversation.domain.AiQuestionTemplate;
import com.ssafy.b209.conversation.domain.AiQuestionTemplateOption;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ResponseMode;
import com.ssafy.b209.conversation.dto.AiQuestionResponse;
import com.ssafy.b209.conversation.dto.BoundingBox;
import com.ssafy.b209.conversation.dto.DetectedObject;
import com.ssafy.b209.conversation.dto.GenerateQuestionCommand;
import com.ssafy.b209.conversation.dto.GeneratedQuestion;
import com.ssafy.b209.conversation.dto.QuestionOption;
import com.ssafy.b209.conversation.dto.SafetyResult;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.repository.AiQuestionTemplateOptionRepository;
import com.ssafy.b209.conversation.repository.AiQuestionTemplateRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.AiQuestionClient;
import com.ssafy.b209.infrastructure.ai.AiQuestionClientException;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ConversationQuestionServiceTest {

  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private AiQuestionTemplateRepository questionTemplateRepository;
  @Mock private AiQuestionTemplateOptionRepository questionTemplateOptionRepository;
  @Mock private AiQuestionClient aiQuestionClient;
  @Mock private QuestionPersistenceService questionPersistenceService;

  private ConversationQuestionService service;
  private ConversationSession session;

  @BeforeEach
  void setUp() {
    service =
        new ConversationQuestionService(
            conversationSessionRepository,
            questionTemplateRepository,
            questionTemplateOptionRepository,
            aiQuestionClient,
            questionPersistenceService);
    session = mock(ConversationSession.class);
    lenient().when(session.getDrawingSessionId()).thenReturn(9L);
    lenient().when(session.getDifficulty()).thenReturn(QuestionDifficulty.LOWER_ELEMENTARY);
    lenient().when(session.getQuestionCount()).thenReturn(2);
    lenient().when(session.getMaxQuestionCount()).thenReturn(10);
    given(session.canAskQuestion()).willReturn(true);
    given(conversationSessionRepository.findById(1L)).willReturn(Optional.of(session));
  }

  @Test
  void sendsOnlyTheTargetContractAndSavesValidAiQuestion() {
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(21L, "무엇을 그리고 있니?", false));

    service.generateQuestion(command(List.of(ResponseMode.VOICE, ResponseMode.OPTION)));

    ArgumentCaptor<com.ssafy.b209.conversation.dto.AiQuestionRequest> requestCaptor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.AiQuestionRequest.class);
    verify(aiQuestionClient).generate(requestCaptor.capture(), any());
    assertThat(requestCaptor.getValue().conversationId()).isEqualTo(1L);
    assertThat(requestCaptor.getValue().drawingSessionId()).isEqualTo(9L);
    assertThat(requestCaptor.getValue().currentQuestionCount()).isEqualTo(2);
    assertThat(requestCaptor.getValue().maxQuestionCount()).isEqualTo(10);

    ArgumentCaptor<QuestionCandidate> candidateCaptor =
        ArgumentCaptor.forClass(QuestionCandidate.class);
    verify(questionPersistenceService).save(eq(1L), candidateCaptor.capture());
    assertThat(candidateCaptor.getValue().questionTemplateId()).isNull();
    assertThat(candidateCaptor.getValue().fallbackUsed()).isFalse();
    assertThatThrownBy(() -> candidateCaptor.getValue().options().add(new QuestionOption("X", "X")))
        .isInstanceOf(UnsupportedOperationException.class);
  }

  @Test
  void doesNotCallAiOrSaveWhenQuestionLimitHasBeenReached() {
    given(session.canAskQuestion()).willReturn(false);

    assertBusinessError(
        () -> service.generateQuestion(command(List.of(ResponseMode.VOICE))),
        ConversationErrorCode.QUESTION_LIMIT_REACHED);

    verify(aiQuestionClient, never()).generate(any(), any());
    verify(questionPersistenceService, never()).save(any(), any());
  }

  @Test
  void usesActiveFallbackForInvalidSuccessSchema() {
    AiQuestionTemplate template = mock(AiQuestionTemplate.class);
    given(template.getId()).willReturn(7L);
    given(template.getQuestionText()).willReturn("이 그림에서 무엇이 가장 눈에 띄니?");
    given(aiQuestionClient.generate(any(), any()))
        .willReturn(
            new AiQuestionResponse(
                "질문", "FOLLOW_UP", List.of(), null, false, passed(), "model", "v1", "p1", 1));
    given(questionTemplateRepository.findFirstByTemplateTypeAndActiveTrueOrderByIdAsc("FALLBACK"))
        .willReturn(Optional.of(template));
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(22L, "이 그림에서 무엇이 가장 눈에 띄니?", true));

    service.generateQuestion(command(List.of(ResponseMode.VOICE)));

    ArgumentCaptor<QuestionCandidate> candidateCaptor =
        ArgumentCaptor.forClass(QuestionCandidate.class);
    verify(questionPersistenceService).save(eq(1L), candidateCaptor.capture());
    assertThat(candidateCaptor.getValue().questionTemplateId()).isEqualTo(7L);
    assertThat(candidateCaptor.getValue().fallbackUsed()).isTrue();
  }

  @Test
  void usesActiveFallbackAfterReadTimeoutWithoutRetryingInService() {
    AiQuestionTemplate template = mock(AiQuestionTemplate.class);
    given(template.getId()).willReturn(7L);
    given(template.getQuestionText()).willReturn("그림 속 이야기를 들려줄래?");
    given(aiQuestionClient.generate(any(), any()))
        .willThrow(new AiQuestionClientException(AiQuestionClientException.Type.READ_TIMEOUT));
    given(questionTemplateRepository.findFirstByTemplateTypeAndActiveTrueOrderByIdAsc("FALLBACK"))
        .willReturn(Optional.of(template));
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(23L, "그림 속 이야기를 들려줄래?", true));

    service.generateQuestion(command(List.of(ResponseMode.VOICE)));

    verify(aiQuestionClient).generate(any(), any());
    verify(questionPersistenceService).save(eq(1L), any());
  }

  @Test
  void doesNotStoreUnsafeAiResponseOrSelectFallbackForSafetyBlock() {
    given(aiQuestionClient.generate(any(), any()))
        .willThrow(
            new AiQuestionClientException(AiQuestionClientException.Type.SAFETY_POLICY_BLOCKED));

    assertBusinessError(
        () -> service.generateQuestion(command(List.of(ResponseMode.VOICE))),
        ConversationErrorCode.AI_SAFETY_POLICY_BLOCKED);

    verify(questionTemplateRepository, never())
        .findFirstByTemplateTypeAndActiveTrueOrderByIdAsc(any());
    verify(questionPersistenceService, never()).save(any(), any());
  }

  @Test
  void doesNotSaveWhenNoActiveFallbackTemplateExists() {
    given(aiQuestionClient.generate(any(), any()))
        .willThrow(
            new AiQuestionClientException(AiQuestionClientException.Type.CONNECTION_FAILURE));
    given(questionTemplateRepository.findFirstByTemplateTypeAndActiveTrueOrderByIdAsc("FALLBACK"))
        .willReturn(Optional.empty());

    assertBusinessError(
        () -> service.generateQuestion(command(List.of(ResponseMode.VOICE))),
        ConversationErrorCode.FALLBACK_QUESTION_NOT_FOUND);

    verify(questionPersistenceService, never()).save(any(), any());
  }

  @Test
  void doesNotSaveFallbackWhenOptionTemplateHasInvalidOptions() {
    AiQuestionTemplate template = mock(AiQuestionTemplate.class);
    AiQuestionTemplateOption duplicateFirst = mock(AiQuestionTemplateOption.class);
    AiQuestionTemplateOption duplicateSecond = mock(AiQuestionTemplateOption.class);
    given(template.getId()).willReturn(7L);
    given(template.getQuestionText()).willReturn("어떤 색을 골랐니?");
    given(duplicateFirst.getOptionKey()).willReturn("A");
    given(duplicateFirst.getLabel()).willReturn("네");
    given(duplicateSecond.getOptionKey()).willReturn("A");
    given(duplicateSecond.getLabel()).willReturn("아니요");
    given(aiQuestionClient.generate(any(), any()))
        .willThrow(new AiQuestionClientException(AiQuestionClientException.Type.READ_TIMEOUT));
    given(questionTemplateRepository.findFirstByTemplateTypeAndActiveTrueOrderByIdAsc("FALLBACK"))
        .willReturn(Optional.of(template));
    given(questionTemplateOptionRepository.findByQuestionTemplateIdOrderByDisplayOrderAsc(7L))
        .willReturn(List.of(duplicateFirst, duplicateSecond));

    assertBusinessError(
        () -> service.generateQuestion(command(List.of(ResponseMode.OPTION))),
        ConversationErrorCode.FALLBACK_QUESTION_NOT_FOUND);

    verify(questionPersistenceService, never()).save(any(), any());
  }

  private GenerateQuestionCommand command(List<ResponseMode> responseModes) {
    return new GenerateQuestionCommand(
        1L,
        9L,
        null,
        8,
        responseModes,
        List.of(new DetectedObject("TREE", "나무", 0.9, new BoundingBox(0.1, 0.2, 0.3, 0.4))),
        List.of(),
        "safety-2026-07");
  }

  private AiQuestionResponse validResponse() {
    return new AiQuestionResponse(
        "무엇을 그리고 있니?",
        "OBJECT_DESCRIPTION",
        List.of(new QuestionOption("TREE", "나무")),
        new DetectedObject("TREE", "나무", 0.9, new BoundingBox(0.1, 0.2, 0.3, 0.4)),
        false,
        passed(),
        "mock-model",
        "1.0",
        "prompt-1",
        12);
  }

  private SafetyResult passed() {
    return new SafetyResult("PASSED", "safety-2026-07", null);
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
