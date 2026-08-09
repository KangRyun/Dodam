package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.repository.AnalysisObservationResultRepository;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.conversation.config.ConversationQuestionLimitProperties;
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

  @Mock private com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository htpAssessmentRepository;
  @Mock private com.ssafy.b209.conversation.repository.ConversationMessageRepository conversationMessageRepository;

  private static final ConversationQuestionLimitProperties QUESTION_LIMITS =
      new ConversationQuestionLimitProperties(5, 5);

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
            observationResultRepository,
            htpAssessmentRepository,
            conversationMessageRepository,
            QUESTION_LIMITS);
    session = mock(ConversationSession.class);
    lenient().when(session.getDrawingSessionId()).thenReturn(9L);
    lenient().when(session.getDifficulty()).thenReturn(QuestionDifficulty.LOWER_ELEMENTARY);
    lenient().when(session.getQuestionCount()).thenReturn(2);
    lenient().when(session.getMaxQuestionCount()).thenReturn(10);
    lenient().when(session.isConversing()).thenReturn(true);
    lenient().when(session.isCompleted()).thenReturn(false);
    // 재개 대상 세션은 상한에 닿아 있어 canAskQuestion 을 아예 부르지 않는다 — lenient 로 둔다.
    lenient().when(session.canAskQuestion()).thenReturn(true);
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
            List.of("TREE", "SUN"),
            true));

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
  void usesActiveFallbackAfterSafetyBlockInsteadOfEndingTheConversation() {
    // 안전 차단도 timeout·연결 실패와 같은 실패로 다룬다. 예전에는 이것만 422로 대화를 끝냈고,
    //   아이가 한마디 거칠게 말해 AI 응답이 규칙에 걸리면 재시도 버튼도 없이 대화가 닫혔다.
    //   ⚠️ 차단된 AI 문장이 아이에게 가는 것이 아니다 — 저장되는 것은 사전 검증된 FALLBACK
    //      템플릿 질문(questionTemplateId=7)뿐이라는 것을 아래에서 못박는다.
    AiQuestionTemplate template = mock(AiQuestionTemplate.class);
    given(template.getId()).willReturn(7L);
    given(template.getQuestionText()).willReturn("그림 속 이야기를 들려줄래?");
    given(aiQuestionClient.generate(any(), any()))
        .willThrow(
            new AiQuestionClientException(AiQuestionClientException.Type.SAFETY_POLICY_BLOCKED));
    given(questionTemplateRepository.findFirstByTemplateTypeAndActiveTrueOrderByIdAsc("FALLBACK"))
        .willReturn(Optional.of(template));
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(24L, "그림 속 이야기를 들려줄래?", true));

    service.generateQuestion(command(List.of(ResponseMode.VOICE)));

    ArgumentCaptor<QuestionCandidate> candidateCaptor =
        ArgumentCaptor.forClass(QuestionCandidate.class);
    verify(questionPersistenceService).save(eq(1L), candidateCaptor.capture());
    assertThat(candidateCaptor.getValue().questionTemplateId()).isEqualTo(7L);
    assertThat(candidateCaptor.getValue().questionText()).isEqualTo("그림 속 이야기를 들려줄래?");
    assertThat(candidateCaptor.getValue().fallbackUsed()).isTrue();
  }

  // ── 그림일기 대화 재개 — 완료 세션 통과 판정 ─────────────────────────────
  @Test
  void generatesAgainWhenACompletedDiaryConversationCanBeReopened() {
    // 그림일기는 대화가 끝난 뒤에도 아이가 계속 그린다. 상한 도달로 끝난 대화는 여기서 막지 않고
    //   통과시키고, 실제 재개(상한 증가)는 잠금을 쥔 QuestionPersistenceService 가 한다.
    given(session.isCompleted()).willReturn(true);
    given(session.isReopenEligible(ConversationQuestionLimitProperties.ABSOLUTE_MAX))
        .willReturn(true);
    given(session.reopenedMaxQuestionCount(5, ConversationQuestionLimitProperties.ABSOLUTE_MAX))
        .willReturn(10);
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(25L, "무엇을 그리고 있니?", false));

    service.generateQuestion(artDiaryCommand(List.of(ResponseMode.VOICE, ResponseMode.OPTION)));

    ArgumentCaptor<com.ssafy.b209.conversation.dto.AiQuestionRequest> requestCaptor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.AiQuestionRequest.class);
    verify(aiQuestionClient).generate(requestCaptor.capture(), any());
    // 재개 후 상한을 미리 싣는다. 옛 상한(=이미 던진 질문 수)을 그대로 보내면 AI가 '마지막 차례'로
    //   읽어, 대화를 다시 여는 바로 그 질문이 맺음말로 나온다.
    assertThat(requestCaptor.getValue().maxQuestionCount()).isEqualTo(10);
    ArgumentCaptor<QuestionCandidate> candidateCaptor =
        ArgumentCaptor.forClass(QuestionCandidate.class);
    verify(questionPersistenceService).save(eq(1L), candidateCaptor.capture());
    // 재개 허가를 저장 계층까지 값으로 들려 보낸다 — 잠금 안에서 활동 유형을 다시 조회하지 않는다.
    assertThat(candidateCaptor.getValue().reopenAllowed()).isTrue();
  }

  @Test
  void doesNotCallAiWhenACompletedDiaryConversationCannotBeReopened() {
    // 아이·보호자가 직접 끝냈거나 이미 절대 상한까지 올라간 대화다 — 그림이 바뀌어도 되살리지 않는다.
    given(session.isCompleted()).willReturn(true);
    given(session.isReopenEligible(ConversationQuestionLimitProperties.ABSOLUTE_MAX))
        .willReturn(false);

    assertBusinessError(
        () -> service.generateQuestion(artDiaryCommand(List.of(ResponseMode.VOICE))),
        ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);

    verify(aiQuestionClient, never()).generate(any(), any());
    verify(questionPersistenceService, never()).save(any(), any());
  }

  @Test
  void doesNotCallAiWhenTheDrawingActivityHasMovedPastConversation() {
    // 그림일기지만 아이가 이미 그림을 끝내고 감정 회고·리포트·완료로 넘어간 활동이다. 되살리면
    //   이미 만들어진 리포트에 없는 말이 완료된 활동에 붙는다. 활동 단계에서 끊기므로 세션 상태
    //   판정(isReopenEligible)까지 가지 않는다 — 그래서 아래는 그것을 stub 하지 않는다.
    given(session.isCompleted()).willReturn(true);

    assertBusinessError(
        () -> service.generateQuestion(artDiaryCommand(List.of(ResponseMode.VOICE), false)),
        ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);

    verify(session, never()).isReopenEligible(anyInt());
    verify(aiQuestionClient, never()).generate(any(), any());
    verify(questionPersistenceService, never()).save(any(), any());
  }

  @Test
  void keepsAnsweringAnOngoingConversationWhateverTheDrawingActivityStageSays() {
    // 회귀 방지: 단계 가드는 재개 경로에만 걸린다. 진행 중(CONVERSING) 대화의 일반 질문은
    //   활동 단계 값이 닫혀 있어도 지금까지와 똑같이 생성·저장돼야 한다.
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(26L, "무엇을 그리고 있니?", false));

    service.generateQuestion(
        artDiaryCommand(List.of(ResponseMode.VOICE, ResponseMode.OPTION), false));

    ArgumentCaptor<QuestionCandidate> candidateCaptor =
        ArgumentCaptor.forClass(QuestionCandidate.class);
    verify(aiQuestionClient).generate(any(), any());
    verify(questionPersistenceService).save(eq(1L), candidateCaptor.capture());
    // 재개가 아니므로 저장 계층에도 재개 허가를 넘기지 않는다.
    assertThat(candidateCaptor.getValue().reopenAllowed()).isFalse();
  }

  @Test
  void neverReopensACompletedHtpConversationEvenWhenTheSessionStateWouldAllowIt() {
    // HTP는 주제마다 대화가 열리고 상한을 다 쓰고 끝나는 것이 정상이다(실측 도달률 100%).
    //   그 대화를 되살리면 '모든 단계 대화가 COMPLETED' 를 요구하는 HTP 검사 완료가 막힌다.
    //   세션 상태 판정(isReopenEligible)까지 가기 전에 활동 유형에서 끊긴다 — 그래서 아래는
    //   isReopenEligible 을 아예 stub 하지 않는다(불렸다면 strict stub 검증에서 드러난다).
    given(session.isCompleted()).willReturn(true);

    assertBusinessError(
        () -> service.generateQuestion(htpCommand()),
        ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);

    verify(session, never()).isReopenEligible(anyInt());
    verify(aiQuestionClient, never()).generate(any(), any());
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

  @Test
  void carriesPreviousSubjectNotesForHtpFollowUpSubjects() {
    // S15P11B209-989 — 주제마다 대화 세션이 새로 열려 다음 주제가 앞 주제 발화를 모른다.
    //   앞 단계를 역추적해 아이 답만 압축해 싣는 배선을 고정한다. 이 목록이 조용히 비면
    //   프롬프트의 [앞 그림에서 아이가 들려준 이야기] 블록 전체가 무효가 된다.
    var priorDrawingSession = mock(com.ssafy.b209.drawing.domain.DrawingSession.class);
    lenient().when(priorDrawingSession.getId()).thenReturn(801L);
    var assessment = mock(com.ssafy.b209.drawing.htp.domain.HtpAssessment.class);
    lenient().when(assessment.getId()).thenReturn(70L);
    var currentStep = mock(com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep.class);
    lenient().when(currentStep.getAssessment()).thenReturn(assessment);
    lenient().when(currentStep.getStepOrder()).thenReturn(2);
    var priorStep = mock(com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep.class);
    lenient().when(priorStep.getDrawingSession()).thenReturn(priorDrawingSession);
    lenient()
        .when(priorStep.getDrawingSubject())
        .thenReturn(com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject.HOUSE);
    given(htpAssessmentRepository.findStepWithAssessmentByDrawingSessionId(9L))
        .willReturn(Optional.of(currentStep));
    given(htpAssessmentRepository.findPriorStepsWithDrawingSession(70L, 2))
        .willReturn(List.of(priorStep));
    var priorConversation = mock(ConversationSession.class);
    lenient().when(priorConversation.getId()).thenReturn(404L);
    given(conversationSessionRepository.findByDrawingSessionId(801L))
        .willReturn(Optional.of(priorConversation));
    given(conversationMessageRepository.findChildAnswerTexts(404L))
        .willReturn(List.of("우리 가족이랑 강아지 살아"));
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(21L, "이 나무한테는 무슨 일이 있었을까?", false));

    service.generateQuestion(htpCommand());

    ArgumentCaptor<com.ssafy.b209.conversation.dto.AiQuestionRequest> requestCaptor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.AiQuestionRequest.class);
    verify(aiQuestionClient).generate(requestCaptor.capture(), any());
    assertThat(requestCaptor.getValue().previousSubjectNotes())
        .containsExactly(
            new com.ssafy.b209.conversation.dto.AiQuestionRequest.PreviousSubjectNote(
                "HOUSE", List.of("우리 가족이랑 강아지 살아")));
  }

  @Test
  void previousSubjectNoteFailureDoesNotBlockQuestionGeneration() {
    // 보조 재료라 역추적이 죽어도 질문 생성은 계속돼야 한다 — 빈 목록으로 진행.
    given(htpAssessmentRepository.findStepWithAssessmentByDrawingSessionId(9L))
        .willThrow(new RuntimeException("boom"));
    given(aiQuestionClient.generate(any(), any())).willReturn(validResponse());
    given(questionPersistenceService.save(eq(1L), any()))
        .willReturn(new GeneratedQuestion(21L, "이 나무한테는 무슨 일이 있었을까?", false));

    service.generateQuestion(htpCommand());

    ArgumentCaptor<com.ssafy.b209.conversation.dto.AiQuestionRequest> requestCaptor =
        ArgumentCaptor.forClass(com.ssafy.b209.conversation.dto.AiQuestionRequest.class);
    verify(aiQuestionClient).generate(requestCaptor.capture(), any());
    assertThat(requestCaptor.getValue().previousSubjectNotes()).isEmpty();
  }

  private GenerateQuestionCommand htpCommand() {
    return new GenerateQuestionCommand(
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
        "TREE",
        List.of(),
        true);
  }

  /** 활동 유형이 그림일기로 확정된 명령 — 대화 재개는 이 유형에서만 허용된다. */
  private GenerateQuestionCommand artDiaryCommand(List<ResponseMode> responseModes) {
    return artDiaryCommand(responseModes, true);
  }

  /**
   * 그림일기 명령에 활동 단계 판정을 실어 만든다.
   *
   * @param responseModes 허용 응답 방식
   * @param drawingActivityOpen 그림 활동이 아직 대화를 더 받을 수 있는 단계인지 여부
   * @return 질문 생성 명령
   */
  private GenerateQuestionCommand artDiaryCommand(
      List<ResponseMode> responseModes, boolean drawingActivityOpen) {
    return new GenerateQuestionCommand(
        1L,
        9L,
        null,
        8,
        responseModes,
        List.of(new DetectedObject("TREE", "나무", 0.9, new BoundingBox(0.1, 0.2, 0.3, 0.4))),
        List.of(),
        "safety-2026-07",
        null,
        "ART_DIARY",
        null,
        List.of(),
        drawingActivityOpen);
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
