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

import com.ssafy.b209.analysis.repository.AnalysisObservationResultRepository;
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
  @Mock private AnalysisObservationResultRepository observationResultRepository;

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
            questionPersistenceService,
            observationResultRepository);
    session = mock(ConversationSession.class);
    lenient().when(session.getDrawingSessionId()).thenReturn(9L);
    lenient().when(session.getDifficulty()).thenReturn(QuestionDifficulty.LOWER_ELEMENTARY);
    lenient().when(session.getQuestionCount()).thenReturn(2);
    lenient().when(session.getMaxQuestionCount()).thenReturn(10);
    lenient().when(session.isConversing()).thenReturn(true);
    lenient().when(session.isCompleted()).thenReturn(false);
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

  // ── HTP 주제·기질문 대상 전달 — S15P11B209-712 ─────────────────────────
  @Test
  void carriesResolvedSubjectContextIntoTheAiRequest() {
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(21L, "무엇을 그리고 있니?", false));

    service.generateQuestion(
        new GenerateQuestionCommand(
            1L,
            9L,
            null,
            8,
            List.of(ResponseMode.VOICE, ResponseMode.OPTION),
            List.of(new DetectedObject("TREE", "나무", 0.9, new BoundingBox(0.1, 0.2, 0.3, 0.4))),
            List.of(),
            "safety-2026-07",
            null,
            "HTP",
            "HOUSE",
            List.of("TREE", "SUN")));

    ArgumentCaptor<com.ssafy.b209.conversation.dto.AiQuestionRequest> captor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.AiQuestionRequest.class);
    verify(aiQuestionClient).generate(captor.capture(), any());
    assertThat(captor.getValue().activityType()).isEqualTo("HTP");
    assertThat(captor.getValue().drawingSubject()).isEqualTo("HOUSE");
    assertThat(captor.getValue().askedObjectCodes()).containsExactly("TREE", "SUN");
  }

  // ── 그림 서술(VLM) 전달 — S15P11B209-704 ──────────────────────────────
  @Test
  void carriesStoredDrawingDescriptionIntoTheAiRequest() {
    given(observationResultRepository.findLatestOverallSummary(77L))
        .willReturn(Optional.of("하늘을 검게 칠했고 사람이 활짝 웃고 있어요."));
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(21L, "무엇을 그리고 있니?", false));

    service.generateQuestion(command(List.of(ResponseMode.VOICE, ResponseMode.OPTION), 77L));

    ArgumentCaptor<com.ssafy.b209.conversation.dto.AiQuestionRequest> captor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.AiQuestionRequest.class);
    verify(aiQuestionClient).generate(captor.capture(), any());
    assertThat(captor.getValue().drawingDescription()).isEqualTo("하늘을 검게 칠했고 사람이 활짝 웃고 있어요.");
  }

  @Test
  void doesNotLookUpDescriptionWhenThereIsNoBasisAnalysis() {
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(21L, "무엇을 그리고 있니?", false));

    service.generateQuestion(command(List.of(ResponseMode.VOICE, ResponseMode.OPTION)));

    // 분석 전 첫 질문은 근거 분석이 없다 — 조회 자체를 하지 않아야 한다.
    verify(observationResultRepository, never()).findLatestOverallSummary(any());
    ArgumentCaptor<com.ssafy.b209.conversation.dto.AiQuestionRequest> captor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.AiQuestionRequest.class);
    verify(aiQuestionClient).generate(captor.capture(), any());
    assertThat(captor.getValue().drawingDescription()).isNull();
  }

  @Test
  void keepsGeneratingWhenTheDescriptionIsMissingOrBlank() {
    // VLM 서술 실패·구버전 데이터가 모두 정상 경로다. 보조 정보 때문에 대화가 끊기면 안 된다.
    given(observationResultRepository.findLatestOverallSummary(77L)).willReturn(Optional.of("   "));
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(21L, "무엇을 그리고 있니?", false));

    service.generateQuestion(command(List.of(ResponseMode.VOICE, ResponseMode.OPTION), 77L));

    ArgumentCaptor<com.ssafy.b209.conversation.dto.AiQuestionRequest> captor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.AiQuestionRequest.class);
    verify(aiQuestionClient).generate(captor.capture(), any());
    assertThat(captor.getValue().drawingDescription()).isNull(); // 공백은 없는 것으로
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
  void carriesTemplateOptionEmojiIntoSavedFallbackOptions() {
    AiQuestionTemplate template = mock(AiQuestionTemplate.class);
    AiQuestionTemplateOption happy = mock(AiQuestionTemplateOption.class);
    AiQuestionTemplateOption unsure = mock(AiQuestionTemplateOption.class);
    given(template.getId()).willReturn(7L);
    given(template.getQuestionText()).willReturn("그림을 그리는 동안 기분이 어땠어?");
    given(happy.getOptionKey()).willReturn("HAPPY");
    given(happy.getLabel()).willReturn("기분이 좋았어요");
    given(happy.getEmoji()).willReturn("😊");
    given(unsure.getOptionKey()).willReturn("NOT_SURE");
    given(unsure.getLabel()).willReturn("잘 모르겠어요");
    given(unsure.getEmoji()).willReturn(null);
    given(aiQuestionClient.generate(any(), any()))
        .willThrow(
            new AiQuestionClientException(AiQuestionClientException.Type.CONNECTION_FAILURE));
    given(questionTemplateRepository.findFirstByTemplateTypeAndActiveTrueOrderByIdAsc("FALLBACK"))
        .willReturn(Optional.of(template));
    given(questionTemplateOptionRepository.findByQuestionTemplateIdOrderByDisplayOrderAsc(7L))
        .willReturn(List.of(happy, unsure));
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(23L, "그림을 그리는 동안 기분이 어땠어?", true));

    service.generateQuestion(command(List.of(ResponseMode.OPTION)));

    ArgumentCaptor<QuestionCandidate> candidateCaptor =
        ArgumentCaptor.forClass(QuestionCandidate.class);
    verify(questionPersistenceService).save(eq(1L), candidateCaptor.capture());
    // Emoji는 Template 선택지에만 있는 값이다. 저장·응답까지 옮기지 않으면 시드한 Emoji가 버려진다.
    assertThat(candidateCaptor.getValue().options())
        .containsExactly(
            new QuestionOption("HAPPY", "기분이 좋았어요", "😊"),
            new QuestionOption("NOT_SURE", "잘 모르겠어요", null));
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
    return command(responseModes, null);
  }

  private GenerateQuestionCommand command(List<ResponseMode> responseModes, Long basisAnalysisId) {
    return new GenerateQuestionCommand(
        1L,
        9L,
        basisAnalysisId,
        8,
        responseModes,
        List.of(new DetectedObject("TREE", "나무", 0.9, new BoundingBox(0.1, 0.2, 0.3, 0.4))),
        List.of(),
        "safety-2026-07");
  }

  @Test
  void carriesConfirmedStopTargetWithoutPersistingIt() {
    // 아이가 되묻기에 말로 그만하겠다고 확인한 응답이다(S15P11B209-951). 맺음말이라 선택 칩이
    // 없지만 OPTION 허용에서도 계약 위반이 아니다 — 질문이 아니라 대화를 닫는 말이기 때문이다.
    given(aiQuestionClient.generate(any(), any()))
        .willReturn(
            new AiQuestionResponse(
                "그래, 오늘 이야기 재미있었어. 그림은 계속 그려도 돼!",
                "FOLLOW_UP",
                null,
                null,
                false,
                passed(),
                "mock-model",
                "1.0",
                "prompt-1",
                12,
                "CONVERSATION"));
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(31L, "그래, 오늘 이야기 재미있었어. 그림은 계속 그려도 돼!", false));

    GeneratedQuestion generated =
        service.generateQuestion(command(List.of(ResponseMode.VOICE, ResponseMode.OPTION)));

    assertThat(generated.confirmedStopTarget()).isEqualTo("CONVERSATION");
    // 저장 계층은 이 신호를 모른다 — 질문 메시지에 남길 내용이 아니라 이번 응답에만 실린다.
    verify(questionPersistenceService).save(eq(1L), any(QuestionCandidate.class));
  }

  @Test
  void fallsBackWhenConfirmedStopTargetIsUnknown() {
    // 모르는 종료 대상으로 대화를 끝내지 않는다. 계약 위반으로 보고 폴백 질문으로 간다.
    AiQuestionTemplate template = mock(AiQuestionTemplate.class);
    given(template.getId()).willReturn(7L);
    given(template.getQuestionText()).willReturn("이 그림에서 무엇이 가장 눈에 띄니?");
    given(aiQuestionClient.generate(any(), any()))
        .willReturn(
            new AiQuestionResponse(
                "맺음말",
                "FOLLOW_UP",
                null,
                null,
                false,
                passed(),
                "mock-model",
                "1.0",
                "prompt-1",
                12,
                "EVERYTHING"));
    given(questionTemplateRepository.findFirstByTemplateTypeAndActiveTrueOrderByIdAsc("FALLBACK"))
        .willReturn(Optional.of(template));
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(22L, "이 그림에서 무엇이 가장 눈에 띄니?", true));

    service.generateQuestion(command(List.of(ResponseMode.VOICE)));

    ArgumentCaptor<QuestionCandidate> candidateCaptor =
        ArgumentCaptor.forClass(QuestionCandidate.class);
    verify(questionPersistenceService).save(eq(1L), candidateCaptor.capture());
    assertThat(candidateCaptor.getValue().fallbackUsed()).isTrue();
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
