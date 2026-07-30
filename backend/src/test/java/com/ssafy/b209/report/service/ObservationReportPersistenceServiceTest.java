package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.domain.AnalysisConversationSummary;
import com.ssafy.b209.analysis.domain.AnalysisObservationResult;
import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.AnalysisConversationSummaryRepository;
import com.ssafy.b209.analysis.repository.AnalysisObservationResultRepository;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.dto.KeyConversationSource;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportActivityNote;
import com.ssafy.b209.report.domain.ReportActivitySummary;
import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import com.ssafy.b209.report.domain.ReportKeyConversation;
import com.ssafy.b209.report.domain.ReportObservedFeature;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ConversationSummaryDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.FollowUpGuideDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.GuardianQuestionDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservationDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservedFeatureDraft;
import com.ssafy.b209.report.exception.MockObservationReportErrorCode;
import com.ssafy.b209.report.repository.ReportActivityNoteRepository;
import com.ssafy.b209.report.repository.ReportActivitySummaryRepository;
import com.ssafy.b209.report.repository.ReportFollowUpGuideRepository;
import com.ssafy.b209.report.repository.ReportGuardianQuestionRepository;
import com.ssafy.b209.report.repository.ReportKeyConversationRepository;
import com.ssafy.b209.report.repository.ReportObservedFeatureRepository;
import com.ssafy.b209.report.repository.ReportRepository;
import java.math.BigDecimal;
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
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;

@ExtendWith(MockitoExtension.class)
class ObservationReportPersistenceServiceTest {

  private static final long ANALYSIS_ID = 701L;
  private static final long REPORT_ID = 900L;
  private static final long DRAWING_SESSION_ID = 100L;
  private static final String ATTENTION_POINTS = "특정 주제에서 응답을 주저하는 패턴이 관찰되었습니다.";
  private static final String DISCLAIMER = "본 결과는 진단이 아니라 관찰 기록입니다.";
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-23T10:31:00Z"), ZoneOffset.UTC);

  @Mock private DrawingAnalysisRepository analysisRepository;
  @Mock private ReportRepository reportRepository;
  @Mock private AnalysisObservationResultRepository observationResultRepository;
  @Mock private AnalysisConversationSummaryRepository conversationSummaryRepository;
  @Mock private ReportActivitySummaryRepository activitySummaryRepository;
  @Mock private ReportActivityNoteRepository activityNoteRepository;
  @Mock private ReportObservedFeatureRepository observedFeatureRepository;
  @Mock private ReportKeyConversationRepository keyConversationRepository;
  @Mock private ReportFollowUpGuideRepository followUpGuideRepository;
  @Mock private ReportGuardianQuestionRepository guardianQuestionRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationMessageRepository conversationMessageRepository;
  @Mock private DrawingSessionEmotionRepository emotionRepository;
  @Mock private HtpAssessmentRepository htpAssessmentRepository;
  @Mock private ApplicationEventPublisher eventPublisher;

  @Captor private ArgumentCaptor<AnalysisObservationResult> observationCaptor;
  @Captor private ArgumentCaptor<AnalysisConversationSummary> conversationCaptor;
  @Captor private ArgumentCaptor<ReportActivitySummary> activitySummaryCaptor;
  @Captor private ArgumentCaptor<List<ReportActivityNote>> notesCaptor;
  @Captor private ArgumentCaptor<List<ReportObservedFeature>> featuresCaptor;
  @Captor private ArgumentCaptor<List<ReportKeyConversation>> keyConversationsCaptor;

  private ObservationReportPersistenceService service;

  @BeforeEach
  void setUp() {
    service =
        new ObservationReportPersistenceService(
            analysisRepository,
            reportRepository,
            observationResultRepository,
            conversationSummaryRepository,
            activitySummaryRepository,
            activityNoteRepository,
            observedFeatureRepository,
            keyConversationRepository,
            followUpGuideRepository,
            guardianQuestionRepository,
            conversationSessionRepository,
            conversationMessageRepository,
            emotionRepository,
            htpAssessmentRepository,
            eventPublisher,
            CLOCK);
  }

  @Test
  void completesStoresNormalizedRowsAndTransitionsStates() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(context(List.of(keyLine(0), keyLine(1))), validResult());

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.SUCCESS);
    assertThat(analysis.getModelName()).isEqualTo("mock-observation-generator");
    assertThat(analysis.getConfidence()).isEqualByComparingTo("0.80");
    assertThat(report.getStatus()).isEqualTo(ReportStatus.COMPLETED);
    assertThat(report.isExpertReviewRecommended()).isFalse();
    assertThat(report.getLimitationsText()).isEqualTo("한계 문구");
    verify(analysis.getDrawingSession()).completeReporting(LocalDateTime.now(CLOCK));

    verify(observationResultRepository).save(observationCaptor.capture());
    assertThat(observationCaptor.getValue().getDisclaimerText()).isEqualTo(DISCLAIMER);
    assertThat(observationCaptor.getValue().getAttentionPoints()).isEqualTo(ATTENTION_POINTS);
    assertThat(observationCaptor.getValue().getReviewStatus().name()).isEqualTo("AI_DRAFT");

    verify(conversationSummaryRepository).save(conversationCaptor.capture());
    assertThat(conversationCaptor.getValue().getQuestionCount()).isEqualTo(3);
    assertThat(conversationCaptor.getValue().getResponseCount()).isEqualTo(2);
    assertThat(conversationCaptor.getValue().getSkippedQuestionCount()).isEqualTo(1);

    verify(activitySummaryRepository).save(activitySummaryCaptor.capture());
    ReportActivitySummary activitySummary = activitySummaryCaptor.getValue();
    assertThat(activitySummary.getConversationQuestionCount()).isEqualTo(3);
    assertThat(activitySummary.isPressureAvailable()).isFalse();
    assertThat(activitySummary.getConversationSummary()).doesNotContain(ATTENTION_POINTS);

    verify(observedFeatureRepository).saveAll(featuresCaptor.capture());
    List<ReportObservedFeature> features = featuresCaptor.getValue();
    assertThat(features).extracting(ReportObservedFeature::getDisplayOrder).containsExactly(0, 1);
    assertThat(features)
        .extracting(ReportObservedFeature::getVisibilityScope)
        .containsExactly(ReportFeatureVisibility.EXPERT_ONLY, ReportFeatureVisibility.EXPERT_ONLY);
    ReportObservedFeature attentionFeature =
        features.stream()
            .filter(feature -> ATTENTION_POINTS.equals(feature.getDescription()))
            .findFirst()
            .orElseThrow();
    assertThat(attentionFeature.getVisibilityScope())
        .isEqualTo(ReportFeatureVisibility.EXPERT_ONLY);

    verify(keyConversationRepository).saveAll(keyConversationsCaptor.capture());
    assertThat(keyConversationsCaptor.getValue())
        .extracting(ReportKeyConversation::getDisplayOrder)
        .containsExactly(0, 1);

    verify(eventPublisher).publishEvent(new AnalysisCompletedEvent(REPORT_ID));
  }

  @Test
  void loadsAggregateConversationCountsFromAllHtpSteps() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    HtpAssessmentStep currentStep = org.mockito.Mockito.mock(HtpAssessmentStep.class);
    HtpAssessment assessment = org.mockito.Mockito.mock(HtpAssessment.class);
    List<HtpAssessmentStep> steps =
        List.of(htpStepWithSession(98L), htpStepWithSession(99L), htpStepWithSession(100L));
    given(currentStep.getAssessment()).willReturn(assessment);
    given(assessment.getSteps()).willReturn(steps);
    given(analysisRepository.findById(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByAnalysisId(ANALYSIS_ID)).willReturn(Optional.of(report));
    given(htpAssessmentRepository.findStepByDrawingSessionId(DRAWING_SESSION_ID))
        .willReturn(Optional.of(currentStep));
    for (int index = 0; index < 3; index++) {
      long sessionId = 98L + index;
      ConversationSession conversation = org.mockito.Mockito.mock(ConversationSession.class);
      given(conversation.getId()).willReturn(300L + index);
      lenient().when(conversation.getDifficultySnapshot()).thenReturn("NORMAL");
      given(conversationSessionRepository.findByDrawingSessionId(sessionId))
          .willReturn(Optional.of(conversation));
      given(conversationMessageRepository.countQuestions(300L + index)).willReturn(2L);
      given(conversationMessageRepository.countAnswered(300L + index)).willReturn(1L);
      given(conversationMessageRepository.countSkipped(300L + index)).willReturn(1L);
      given(conversationMessageRepository.countUnrecognizedSpeech(300L + index)).willReturn(0L);
      given(conversationMessageRepository.findKeyConversationSources(300L + index))
          .willReturn(List.of());
    }
    given(
            emotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
                    List.of(98L, 99L, 100L)))
        .willReturn(List.of());

    ObservationGenerationContext context = service.loadContext(ANALYSIS_ID).orElseThrow();

    assertThat(context.questionCount()).isEqualTo(6);
    assertThat(context.answeredCount()).isEqualTo(3);
    assertThat(context.skippedCount()).isEqualTo(3);
    // 서술·탐지 코드·문답이 전부 빈 주제는 담지 않는다(S15P11B209-741) — 프롬프트 노이즈 방지.
    assertThat(context.subjectContexts()).isEmpty();
  }

  @Test
  void loadsSubjectContextsPerHtpStepInStepOrder() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    HtpAssessmentStep currentStep = org.mockito.Mockito.mock(HtpAssessmentStep.class);
    HtpAssessment assessment = org.mockito.Mockito.mock(HtpAssessment.class);
    // getSteps()가 저장 순서를 보장하지 않아도 stepOrder로 정렬됨을 함께 검증한다(역순 제공).
    List<HtpAssessmentStep> steps =
        List.of(
            htpStepWithSession(100L, 2, HtpDrawingSubject.PERSON),
            htpStepWithSession(99L, 1, HtpDrawingSubject.TREE),
            htpStepWithSession(98L, 0, HtpDrawingSubject.HOUSE));
    given(currentStep.getAssessment()).willReturn(assessment);
    given(assessment.getSteps()).willReturn(steps);
    given(analysisRepository.findById(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByAnalysisId(ANALYSIS_ID)).willReturn(Optional.of(report));
    given(htpAssessmentRepository.findStepByDrawingSessionId(DRAWING_SESSION_ID))
        .willReturn(Optional.of(currentStep));

    // 집(98L): 서술 + 탐지 코드 + 문답이 모두 있는 주제.
    AnalysisObservationResult houseObservation =
        org.mockito.Mockito.mock(AnalysisObservationResult.class);
    DrawingAnalysis houseAnalysis = org.mockito.Mockito.mock(DrawingAnalysis.class);
    DrawingDetectedObject houseDoor = org.mockito.Mockito.mock(DrawingDetectedObject.class);
    given(houseObservation.getOverallSummary()).willReturn("가운데에 집이 크게 그려져 있어요.");
    given(houseObservation.getAnalysis()).willReturn(houseAnalysis);
    given(houseAnalysis.getDetections()).willReturn(List.of(houseDoor));
    given(houseDoor.getLabel()).willReturn("HOUSE_DOOR");
    given(observationResultRepository.findLatestByDrawingSessionId(98L))
        .willReturn(Optional.of(houseObservation));

    ConversationSession houseConversation = org.mockito.Mockito.mock(ConversationSession.class);
    given(houseConversation.getId()).willReturn(300L);
    lenient().when(houseConversation.getDifficultySnapshot()).thenReturn("NORMAL");
    given(conversationSessionRepository.findByDrawingSessionId(98L))
        .willReturn(Optional.of(houseConversation));
    KeyConversationSource houseQa = org.mockito.Mockito.mock(KeyConversationSource.class);
    lenient().when(houseQa.getQuestionMessageId()).thenReturn(1L);
    given(houseQa.getQuestionText()).willReturn("이 집에는 누가 살아?");
    lenient().when(houseQa.getAnswerMessageId()).thenReturn(2L);
    given(houseQa.getAnswerText()).willReturn("엄마랑 나!");
    given(houseQa.getAnswerType()).willReturn("VOICE_ANSWER");
    given(conversationMessageRepository.findKeyConversationSources(300L))
        .willReturn(List.of(houseQa));

    // 나무(99L): 서술만 있고 대화는 건너뛴 주제 — 그래도 담긴다.
    AnalysisObservationResult treeObservation =
        org.mockito.Mockito.mock(AnalysisObservationResult.class);
    DrawingAnalysis treeAnalysis = org.mockito.Mockito.mock(DrawingAnalysis.class);
    given(treeObservation.getOverallSummary()).willReturn("나무에 열매가 세 개 달려 있어요.");
    given(treeObservation.getAnalysis()).willReturn(treeAnalysis);
    given(treeAnalysis.getDetections()).willReturn(List.of());
    given(observationResultRepository.findLatestByDrawingSessionId(99L))
        .willReturn(Optional.of(treeObservation));
    given(conversationSessionRepository.findByDrawingSessionId(99L)).willReturn(Optional.empty());

    // 사람(100L): 서술·문답·코드 전부 없음 — 담지 않는다.
    given(observationResultRepository.findLatestByDrawingSessionId(100L))
        .willReturn(Optional.empty());
    given(conversationSessionRepository.findByDrawingSessionId(100L)).willReturn(Optional.empty());

    given(
            emotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
                    List.of(98L, 99L, 100L)))
        .willReturn(List.of());

    ObservationGenerationContext context = service.loadContext(ANALYSIS_ID).orElseThrow();

    assertThat(context.subjectContexts()).hasSize(2);
    ObservationGenerationContext.SubjectContext house = context.subjectContexts().get(0);
    assertThat(house.drawingSubject()).isEqualTo("HOUSE");
    assertThat(house.drawingDescription()).isEqualTo("가운데에 집이 크게 그려져 있어요.");
    assertThat(house.detectedObjectCodes()).containsExactly("HOUSE_DOOR");
    assertThat(house.qaPairs()).hasSize(1);
    assertThat(house.qaPairs().get(0).questionText()).isEqualTo("이 집에는 누가 살아?");
    assertThat(house.qaPairs().get(0).answerText()).isEqualTo("엄마랑 나!");
    ObservationGenerationContext.SubjectContext tree = context.subjectContexts().get(1);
    assertThat(tree.drawingSubject()).isEqualTo("TREE");
    assertThat(tree.qaPairs()).isEmpty();
    // 평탄 keyConversations에도 같은 문답이 실린다(리포트 저장용 — 기존 동작 유지).
    assertThat(context.keyConversations()).hasSize(1);
  }

  @Test
  void loadsSingleSubjectContextWithoutHtpAssessment() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findById(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByAnalysisId(ANALYSIS_ID)).willReturn(Optional.of(report));
    given(htpAssessmentRepository.findStepByDrawingSessionId(DRAWING_SESSION_ID))
        .willReturn(Optional.empty());
    given(conversationSessionRepository.findByDrawingSessionId(DRAWING_SESSION_ID))
        .willReturn(Optional.empty());

    AnalysisObservationResult observation =
        org.mockito.Mockito.mock(AnalysisObservationResult.class);
    DrawingAnalysis observationAnalysis = org.mockito.Mockito.mock(DrawingAnalysis.class);
    given(observation.getOverallSummary()).willReturn("공룡이 풍선을 들고 있어요.");
    given(observation.getAnalysis()).willReturn(observationAnalysis);
    given(observationAnalysis.getDetections()).willReturn(List.of());
    given(observationResultRepository.findLatestByDrawingSessionId(DRAWING_SESSION_ID))
        .willReturn(Optional.of(observation));

    given(
            emotionRepository.findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
                DRAWING_SESSION_ID))
        .willReturn(List.of());

    ObservationGenerationContext context = service.loadContext(ANALYSIS_ID).orElseThrow();

    assertThat(context.subjectContexts()).hasSize(1);
    ObservationGenerationContext.SubjectContext subject = context.subjectContexts().get(0);
    // 그림일기(HTP 아님)는 주제가 없다 — AI 계약의 drawingSubject=null과 1:1.
    assertThat(subject.drawingSubject()).isNull();
    assertThat(subject.drawingDescription()).isEqualTo("공룡이 풍선을 들고 있어요.");
  }

  @Test
  void completeDoesNotPublishAnalysisCompletedWhenReportAlreadyCompleted() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    report.complete(false, "이미 완료", LocalDateTime.now(CLOCK));
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(emptyConversationContext(), validResult());

    verify(eventPublisher, never()).publishEvent(any());
  }

  @Test
  void clampsAiSuppliedReviewedGuardianToExpertOnly() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(emptyConversationContext(), resultWithReviewedGuardianFeature());

    verify(observedFeatureRepository).saveAll(featuresCaptor.capture());
    assertThat(featuresCaptor.getValue())
        .extracting(ReportObservedFeature::getVisibilityScope)
        .containsOnly(ReportFeatureVisibility.EXPERT_ONLY);
  }

  @Test
  void completesStoresZeroCountsForEmptyConversation() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(emptyConversationContext(), validResult());

    verify(conversationSummaryRepository).save(conversationCaptor.capture());
    assertThat(conversationCaptor.getValue().getQuestionCount()).isZero();
    assertThat(conversationCaptor.getValue().getResponseCount()).isZero();
    verify(keyConversationRepository).saveAll(keyConversationsCaptor.capture());
    assertThat(keyConversationsCaptor.getValue()).isEmpty();
    assertThat(report.getStatus()).isEqualTo(ReportStatus.COMPLETED);
  }

  @Test
  void completesHtpAggregateWithoutRecompletingPersonDrawingSession() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    HtpAssessment assessment = org.mockito.Mockito.mock(HtpAssessment.class);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));
    given(htpAssessmentRepository.findByStepDrawingSessionIdForUpdate(DRAWING_SESSION_ID))
        .willReturn(Optional.of(assessment));

    service.complete(emptyConversationContext(), validResult());

    verify(assessment).completeAnalysis(LocalDateTime.now(CLOCK));
    verify(analysis.getDrawingSession(), never()).completeReporting(any());
  }

  @Test
  void completeSkipsWhenAnalysisAlreadySucceeded() {
    DrawingAnalysis analysis = pendingAnalysis();
    analysis.succeedFinal("mock", "1.0", null, LocalDateTime.now(CLOCK));
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));

    service.complete(emptyConversationContext(), validResult());

    verify(reportRepository, never()).findByIdForUpdate(anyLong());
    verify(observationResultRepository, never()).save(any());
  }

  @Test
  void completeSkipsWhenReportAlreadyCompleted() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    report.complete(false, "이미 완료", LocalDateTime.now(CLOCK));
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(emptyConversationContext(), validResult());

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.PENDING);
    verify(observationResultRepository, never()).save(any());
  }

  @Test
  void completeThrowsWhenAnalysisMissing() {
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.empty());

    assertThatThrownBy(() -> service.complete(emptyConversationContext(), validResult()))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(MockObservationReportErrorCode.ANALYSIS_NOT_FOUND));
  }

  @Test
  void completeThrowsWhenReportMissing() {
    DrawingAnalysis analysis = pendingAnalysis();
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.empty());

    assertThatThrownBy(() -> service.complete(emptyConversationContext(), validResult()))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(MockObservationReportErrorCode.REPORT_NOT_FOUND));
  }

  @Test
  void markFailedTransitionsPendingAnalysisAndGeneratingReport() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.markFailed(ANALYSIS_ID, REPORT_ID, "TIMEOUT", "생성 실패");

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.FAILED);
    assertThat(analysis.getErrorCode()).isEqualTo("TIMEOUT");
    assertThat(report.getStatus()).isEqualTo(ReportStatus.FAILED);
    assertThat(report.getFailureReason()).isEqualTo("TIMEOUT");
    assertThat(report.getFailedAt()).isEqualTo(LocalDateTime.now(CLOCK));
    verify(analysis.getDrawingSession()).failReporting();
  }

  @Test
  void marksHtpAggregateFailedWithoutFailingCompletedPersonSession() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    HtpAssessment assessment = org.mockito.Mockito.mock(HtpAssessment.class);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));
    given(htpAssessmentRepository.findByStepDrawingSessionIdForUpdate(DRAWING_SESSION_ID))
        .willReturn(Optional.of(assessment));

    service.markFailed(ANALYSIS_ID, REPORT_ID, "TIMEOUT", "생성 실패");

    verify(assessment).failAnalysis();
    verify(analysis.getDrawingSession(), never()).failReporting();
  }

  @Test
  void markFailedSkipsWhenAnalysisNotPending() {
    DrawingAnalysis analysis = pendingAnalysis();
    analysis.succeedFinal("mock", "1.0", null, LocalDateTime.now(CLOCK));
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    lenient().when(reportRepository.findByIdForUpdate(REPORT_ID)).thenReturn(Optional.empty());

    service.markFailed(ANALYSIS_ID, REPORT_ID, "TIMEOUT", "생성 실패");

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.SUCCESS);
  }

  private DrawingAnalysis pendingAnalysis() {
    DrawingSession session = org.mockito.Mockito.mock(DrawingSession.class);
    lenient().when(session.getId()).thenReturn(DRAWING_SESSION_ID);
    return DrawingAnalysis.pending(
        session,
        org.mockito.Mockito.mock(DrawingAsset.class),
        DrawingAnalysisType.ACTIVITY_REPORT,
        "completion-key-1234",
        LocalDateTime.of(2026, 7, 23, 10, 30));
  }

  private HtpAssessmentStep htpStepWithSession(Long sessionId) {
    // 주제·순서는 임의 기본값 — 주제별 수집(741)이 step에서 항상 읽으므로 stub이 필수다.
    return htpStepWithSession(sessionId, 0, HtpDrawingSubject.HOUSE);
  }

  private HtpAssessmentStep htpStepWithSession(
      Long sessionId, int stepOrder, HtpDrawingSubject subject) {
    HtpAssessmentStep step = org.mockito.Mockito.mock(HtpAssessmentStep.class);
    DrawingSession session = org.mockito.Mockito.mock(DrawingSession.class);
    lenient().when(session.getId()).thenReturn(sessionId);
    given(step.getDrawingSession()).willReturn(session);
    given(step.getDrawingSubject()).willReturn(subject);
    lenient().when(step.getStepOrder()).thenReturn(stepOrder);
    return step;
  }

  private Report generatingReport(DrawingAnalysis analysis) {
    return Report.generating(
        org.mockito.Mockito.mock(DrawingSession.class),
        analysis,
        1,
        LocalDateTime.of(2026, 7, 23, 10, 30));
  }

  private ObservationGenerationContext context(
      List<ObservationGenerationContext.KeyConversationLine> keyConversations) {
    return new ObservationGenerationContext(
        ANALYSIS_ID,
        DRAWING_SESSION_ID,
        REPORT_ID,
        null,
        "NORMAL",
        3,
        2,
        1,
        0,
        List.of("HAPPY"),
        "행복했어요",
        keyConversations,
        List.of());
  }

  private ObservationGenerationContext emptyConversationContext() {
    return new ObservationGenerationContext(
        ANALYSIS_ID,
        DRAWING_SESSION_ID,
        REPORT_ID,
        null,
        null,
        0,
        0,
        0,
        0,
        List.of(),
        null,
        List.of(),
        List.of());
  }

  private ObservationGenerationContext.KeyConversationLine keyLine(int index) {
    return new ObservationGenerationContext.KeyConversationLine(
        (long) (index + 1), "질문 " + index, (long) (index + 100), "답변 " + index, "OPTION_ANSWER");
  }

  private ObservationGenerationResult validResult() {
    return new ObservationGenerationResult(
        "request-1",
        "mock-observation-generator",
        "1.0",
        new BigDecimal("0.80"),
        new ObservationDraft(
            "AI_DRAFT",
            "전체 요약",
            "긍정 신호",
            ATTENTION_POINTS,
            "근거 요약",
            "보호자 안내",
            "후속 질문",
            false,
            DISCLAIMER,
            List.of(
                new ObservedFeatureDraft("ENGAGE", "몰입", "적극적으로 표현", "관찰 근거", "REVIEWED_GUARDIAN"),
                new ObservedFeatureDraft(
                    "HESITATE", "주저", ATTENTION_POINTS, "관찰 근거", "EXPERT_ONLY"))),
        new ConversationSummaryDraft("보호자용 대화 요약", "오늘의 그림", "즐거움", "SELECTED", "즐거웠어요"),
        List.of("색을 여러 번 바꾸었습니다.", "잠시 생각하는 시간을 가졌습니다."),
        List.of(new FollowUpGuideDraft("개방형 질문을 해보세요.", "정답을 요구하지 마세요.")),
        List.of(new GuardianQuestionDraft("어떤 기분이었어?", "감정 표현 유도")),
        "한계 문구");
  }

  private ObservationGenerationResult resultWithReviewedGuardianFeature() {
    return new ObservationGenerationResult(
        "request-1",
        "mock-observation-generator",
        "1.0",
        new BigDecimal("0.80"),
        new ObservationDraft(
            "AI_DRAFT",
            "전체 요약",
            "긍정 신호",
            ATTENTION_POINTS,
            "근거 요약",
            "보호자 안내",
            "후속 질문",
            false,
            DISCLAIMER,
            List.of(
                new ObservedFeatureDraft("ENGAGE", "몰입", "적극적으로 표현", "관찰 근거", "REVIEWED_GUARDIAN"),
                new ObservedFeatureDraft("MORE", "추가", "또 다른 관찰", "관찰 근거", "REVIEWED_GUARDIAN"))),
        new ConversationSummaryDraft("보호자용 대화 요약", "오늘의 그림", "즐거움", "SELECTED", null),
        List.of(),
        List.of(),
        List.of(),
        "한계 문구");
  }
}
