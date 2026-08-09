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
import com.ssafy.b209.analysis.domain.DrawingCoordinateSpace;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.domain.ObservationReviewStatus;
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
import com.ssafy.b209.drawing.service.StrokeBehaviorSummary;
import com.ssafy.b209.drawing.service.StrokeBehaviorSummaryService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportActivityNote;
import com.ssafy.b209.report.domain.ReportActivitySummary;
import com.ssafy.b209.report.domain.ReportDiaryCaregiverQuestion;
import com.ssafy.b209.report.domain.ReportDiaryInsight;
import com.ssafy.b209.report.domain.ReportDiaryStoryComponent;
import com.ssafy.b209.report.domain.ReportDiaryTranscriptEntry;
import com.ssafy.b209.report.domain.ReportDiaryVisualObservation;
import com.ssafy.b209.report.domain.ReportDrawnItem;
import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import com.ssafy.b209.report.domain.ReportGuardianQuestion;
import com.ssafy.b209.report.domain.ReportKeyConversation;
import com.ssafy.b209.report.domain.ReportObservedFeature;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ObservationGeneration;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ConversationSummaryDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DiaryCaregiverQuestionDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DiaryDataScopeDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DiaryDrawingObservationDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DiaryEvidenceRefDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DiaryInsightsDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DiaryStoryComponentDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DrawnItemDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.FollowUpGuideDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.GuardianQuestionDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservationDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservedFeatureDraft;
import com.ssafy.b209.report.exception.MockObservationReportErrorCode;
import com.ssafy.b209.report.repository.ReportActivityNoteRepository;
import com.ssafy.b209.report.repository.ReportActivitySummaryRepository;
import com.ssafy.b209.report.repository.ReportDiaryCaregiverQuestionRepository;
import com.ssafy.b209.report.repository.ReportDiaryChildVoiceRepository;
import com.ssafy.b209.report.repository.ReportDiaryDevelopmentSourceRepository;
import com.ssafy.b209.report.repository.ReportDiaryDevelopmentalObservationRepository;
import com.ssafy.b209.report.repository.ReportDiaryEvidenceRefRepository;
import com.ssafy.b209.report.repository.ReportDiaryInsightAlternativeRepository;
import com.ssafy.b209.report.repository.ReportDiaryInsightRepository;
import com.ssafy.b209.report.repository.ReportDiaryNarrativeStepRepository;
import com.ssafy.b209.report.repository.ReportDiarySessionObservationRepository;
import com.ssafy.b209.report.repository.ReportDiaryStoryComponentRepository;
import com.ssafy.b209.report.repository.ReportDiaryTranscriptEntryRepository;
import com.ssafy.b209.report.repository.ReportDiaryUnknownItemRepository;
import com.ssafy.b209.report.repository.ReportDiaryVisualObservationRepository;
import com.ssafy.b209.report.repository.ReportDrawnItemRepository;
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
import java.util.Set;
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
  // 786에서 리포트 프롬프트가 갈린 뒤 AI가 실제로 보내는 재현성 태그 형식과 길이(그림일기 78자)다.
  private static final String SPLIT_PROMPT_MODEL_VERSION =
      "pipeline=0.1.0;prompt=report_common@1.3.0+195ae9fc;report_diary@1.3.0+05f29d3b";
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-23T10:31:00Z"), ZoneOffset.UTC);

  @Mock private DrawingAnalysisRepository analysisRepository;
  @Mock private ReportRepository reportRepository;
  @Mock private AnalysisObservationResultRepository observationResultRepository;
  @Mock private AnalysisConversationSummaryRepository conversationSummaryRepository;
  @Mock private ReportActivitySummaryRepository activitySummaryRepository;
  @Mock private ReportActivityNoteRepository activityNoteRepository;
  @Mock private ReportDrawnItemRepository drawnItemRepository;

  @Mock
  private com.ssafy.b209.report.repository.ReportPublicInterpretationRepository
      interpretationRepository;

  @Mock
  private com.ssafy.b209.report.repository.ReportEvidenceItemRepository evidenceItemRepository;

  @Mock private com.ssafy.b209.report.repository.ReportParentGuideRepository parentGuideRepository;
  @Mock private com.ssafy.b209.report.repository.ReportCrisisAlertRepository crisisAlertRepository;
  @Mock private com.ssafy.b209.report.repository.ReportSubjectRepository subjectRepository;
  @Mock private com.ssafy.b209.report.repository.ReportReferenceRepository referenceRepository;

  private final com.ssafy.b209.report.safety.InterpretationSafetyVerifier safetyVerifier =
      new com.ssafy.b209.report.safety.InterpretationSafetyVerifier();
  private final InterpretationCandidateAdapter candidateAdapter =
      new InterpretationCandidateAdapter();
  @Mock private ReportObservedFeatureRepository observedFeatureRepository;
  @Mock private ReportKeyConversationRepository keyConversationRepository;
  @Mock private ReportFollowUpGuideRepository followUpGuideRepository;
  @Mock private ReportDiaryInsightRepository diaryInsightRepository;
  @Mock private ReportDiaryNarrativeStepRepository diaryNarrativeStepRepository;
  @Mock private ReportDiaryChildVoiceRepository diaryChildVoiceRepository;
  @Mock private ReportDiarySessionObservationRepository diarySessionObservationRepository;
  @Mock private ReportDiaryCaregiverQuestionRepository diaryCaregiverQuestionRepository;
  @Mock private ReportDiaryEvidenceRefRepository diaryEvidenceRefRepository;
  @Mock private ReportDiaryInsightAlternativeRepository diaryAlternativeRepository;

  @Mock
  private ReportDiaryDevelopmentalObservationRepository diaryDevelopmentalObservationRepository;

  @Mock private ReportDiaryDevelopmentSourceRepository diaryDevelopmentSourceRepository;
  @Mock private ReportDiaryUnknownItemRepository diaryUnknownItemRepository;
  @Mock private ReportDiaryStoryComponentRepository diaryStoryComponentRepository;
  @Mock private ReportDiaryVisualObservationRepository diaryVisualObservationRepository;
  @Mock private ReportDiaryTranscriptEntryRepository diaryTranscriptEntryRepository;
  private final DiaryTranscriptSnapshotFactory diaryTranscriptSnapshotFactory =
      new DiaryTranscriptSnapshotFactory();
  @Mock private ReportGuardianQuestionRepository guardianQuestionRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private ConversationMessageRepository conversationMessageRepository;
  @Mock private DrawingSessionEmotionRepository emotionRepository;
  @Mock private HtpAssessmentRepository htpAssessmentRepository;
  @Mock private ApplicationEventPublisher eventPublisher;

  @Mock private StrokeBehaviorSummaryService behaviorSummaryService;

  @Captor private ArgumentCaptor<AnalysisObservationResult> observationCaptor;
  @Captor private ArgumentCaptor<AnalysisConversationSummary> conversationCaptor;
  @Captor private ArgumentCaptor<ReportActivitySummary> activitySummaryCaptor;
  @Captor private ArgumentCaptor<List<ReportActivityNote>> notesCaptor;
  @Captor private ArgumentCaptor<List<ReportDrawnItem>> drawnItemsCaptor;
  @Captor private ArgumentCaptor<List<ReportDiaryCaregiverQuestion>> caregiverQuestionsCaptor;
  @Captor private ArgumentCaptor<ReportDiaryInsight> diaryInsightCaptor;
  @Captor private ArgumentCaptor<List<ReportDiaryStoryComponent>> storyComponentsCaptor;
  @Captor private ArgumentCaptor<List<ReportDiaryVisualObservation>> visualObservationsCaptor;
  @Captor private ArgumentCaptor<List<ReportDiaryTranscriptEntry>> transcriptEntriesCaptor;
  @Captor private ArgumentCaptor<List<ReportObservedFeature>> featuresCaptor;
  @Captor private ArgumentCaptor<List<ReportKeyConversation>> keyConversationsCaptor;
  @Captor private ArgumentCaptor<List<ReportGuardianQuestion>> guardianQuestionsCaptor;

  @Captor private ArgumentCaptor<List<com.ssafy.b209.report.domain.ReportSubject>> subjectsCaptor;

  @Captor
  private ArgumentCaptor<List<com.ssafy.b209.report.domain.ReportReference>> referencesCaptor;

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
            drawnItemRepository,
            interpretationRepository,
            evidenceItemRepository,
            parentGuideRepository,
            crisisAlertRepository,
            subjectRepository,
            referenceRepository,
            safetyVerifier,
            candidateAdapter,
            observedFeatureRepository,
            keyConversationRepository,
            followUpGuideRepository,
            diaryInsightRepository,
            diaryNarrativeStepRepository,
            diaryChildVoiceRepository,
            diarySessionObservationRepository,
            diaryCaregiverQuestionRepository,
            diaryEvidenceRefRepository,
            diaryAlternativeRepository,
            diaryDevelopmentalObservationRepository,
            diaryDevelopmentSourceRepository,
            diaryUnknownItemRepository,
            diaryStoryComponentRepository,
            diaryVisualObservationRepository,
            diaryTranscriptEntryRepository,
            diaryTranscriptSnapshotFactory,
            guardianQuestionRepository,
            conversationSessionRepository,
            conversationMessageRepository,
            emotionRepository,
            htpAssessmentRepository,
            behaviorSummaryService,
            eventPublisher,
            CLOCK);
  }

  @Test
  void storesAggregatedDrawingBehaviorNumbersInActivitySummary() {
    // 772가 집계해 AI로 보내던 수치가 리포트에는 한 자리도 남지 않아 보호자가 볼 수 없었다(S15P11B209-870).
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));
    given(behaviorSummaryService.summarizeAll(List.of(DRAWING_SESSION_ID)))
        .willReturn(
            Optional.of(
                new StrokeBehaviorSummary(
                    261_000L, 180_000L, 37, 4, 2, 5, 1, 3, Set.of("#ff0000"), true, false)));

    service.complete(context(List.of(keyLine(0))), new ObservationGeneration(validResult(), null));

    verify(activitySummaryRepository).save(activitySummaryCaptor.capture());
    ReportActivitySummary activitySummary = activitySummaryCaptor.getValue();
    assertThat(activitySummary.getDrawingDurationMs()).isEqualTo(261_000L);
    assertThat(activitySummary.getPauseCount()).isEqualTo(4);
    assertThat(activitySummary.getEraseCount()).isEqualTo(5);
    assertThat(activitySummary.isPressureAvailable()).isTrue();
  }

  @Test
  void storesTheAiResponseRawJsonSoNothingIsLostAtReadTime() {
    // 계약 스키마로 읽는 순간 스키마 밖 서술이 사라진다. 조회 때는 만들 수 없으니 생성할 때
    //   원문을 함께 저장해야 한다(S15P11B209-980).
    String rawJson = "{\"requestId\":\"r-1\",\"스키마에 없는 필드\":\"버려지던 서술\"}";
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        context(List.of(keyLine(0))), new ObservationGeneration(validResult(), rawJson));

    assertThat(report.getAiRawReport()).isEqualTo(rawJson);
  }

  @Test
  void persistsCaregiverConnectionTypeAndStaticResponseGuide() {
    // "오늘 마음 나누기" 교감 카드는 유형·공감 반응 안내·함께 해보기를 그대로 저장해야 앱이 카드로 조립한다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        context(List.of(keyLine(0))),
        new ObservationGeneration(resultWithCaregiverConnection(), null));

    verify(diaryCaregiverQuestionRepository).saveAll(caregiverQuestionsCaptor.capture());
    List<ReportDiaryCaregiverQuestion> saved = caregiverQuestionsCaptor.getValue();
    assertThat(saved).hasSize(1);
    ReportDiaryCaregiverQuestion card = saved.get(0);
    assertThat(card.getConnectionType()).isEqualTo("FEELING_SHARING");
    assertThat(card.getResponseGuide()).contains("마음을 그대로 받아 주세요");
    assertThat(card.getCoRegulationAction()).contains("같이 그려 볼까요");
  }

  @Test
  void persistsV3ScopeStoryComponentsVisualObservationsAndTranscript() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    ObservationGenerationContext context =
        context(
            List.of(
                new ObservationGenerationContext.KeyConversationLine(
                    11L,
                    "누구와 함께 있었어?",
                    21L,
                    "친구랑 놀았어요",
                    "VOICE_ANSWER",
                    false,
                    "SUCCESS",
                    true,
                    LocalDateTime.of(2026, 8, 9, 10, 15))));
    service.complete(context, new ObservationGeneration(resultWithV3DiaryInsights(), null));

    verify(diaryInsightRepository).save(diaryInsightCaptor.capture());
    assertThat(diaryInsightCaptor.getValue().getSchemaVersion()).isEqualTo(3);
    assertThat(diaryInsightCaptor.getValue().getEvidenceLevel()).isEqualTo("PARTIAL");
    assertThat(diaryInsightCaptor.getValue().getVisualObservationCount()).isEqualTo(1);
    verify(diaryStoryComponentRepository).saveAll(storyComponentsCaptor.capture());
    assertThat(storyComponentsCaptor.getValue())
        .extracting(ReportDiaryStoryComponent::getComponentType)
        .containsExactly("EVENT", "EMOTION");
    verify(diaryVisualObservationRepository).saveAll(visualObservationsCaptor.capture());
    assertThat(visualObservationsCaptor.getValue())
        .singleElement()
        .extracting(ReportDiaryVisualObservation::getText)
        .isEqualTo("화면 중앙에 두 사람이 나란히 있어요.");
    verify(diaryTranscriptEntryRepository).saveAll(transcriptEntriesCaptor.capture());
    assertThat(transcriptEntriesCaptor.getValue())
        .singleElement()
        .extracting(ReportDiaryTranscriptEntry::getResponseType)
        .isEqualTo("VOICE");
  }

  @Test
  void leavesTheAiRawReportEmptyWhenTheResponseBodyWasNotCaptured() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(context(List.of(keyLine(0))), new ObservationGeneration(validResult(), " "));

    assertThat(report.getAiRawReport()).isNull();
  }

  @Test
  void keepsBehaviorNumbersNullWhenNoStrokeBatchExists() {
    // 측정하지 못한 값을 0으로 채우면 "한 번도 멈추지 않았다"는 관찰로 읽힌다. null로 남긴다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));
    given(behaviorSummaryService.summarizeAll(List.of(DRAWING_SESSION_ID)))
        .willReturn(Optional.empty());

    service.complete(context(List.of(keyLine(0))), new ObservationGeneration(validResult(), null));

    verify(activitySummaryRepository).save(activitySummaryCaptor.capture());
    ReportActivitySummary activitySummary = activitySummaryCaptor.getValue();
    assertThat(activitySummary.getDrawingDurationMs()).isNull();
    assertThat(activitySummary.getPauseCount()).isNull();
    assertThat(activitySummary.getEraseCount()).isNull();
    assertThat(activitySummary.isPressureAvailable()).isFalse();
  }

  @Test
  void completesReportEvenWhenBehaviorAggregationFails() {
    // 행동 수치는 부가 정보다. MongoDB 장애로 리포트 전체를 잃지 않는다(S15P11B209-815 실패 확산 방지).
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));
    given(behaviorSummaryService.summarizeAll(List.of(DRAWING_SESSION_ID)))
        .willThrow(new IllegalStateException("mongo down"));

    service.complete(context(List.of(keyLine(0))), new ObservationGeneration(validResult(), null));

    assertThat(report.getStatus()).isEqualTo(ReportStatus.COMPLETED);
    verify(activitySummaryRepository).save(activitySummaryCaptor.capture());
    assertThat(activitySummaryCaptor.getValue().getDrawingDurationMs()).isNull();
  }

  @Test
  void completesStoresNormalizedRowsAndTransitionsStates() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        context(List.of(keyLine(0), keyLine(1))), new ObservationGeneration(validResult(), null));

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.SUCCESS);
    assertThat(analysis.getModelName()).isEqualTo("mock-observation-generator");
    assertThat(analysis.getConfidence()).isEqualByComparingTo("0.80");
    assertThat(report.getStatus()).isEqualTo(ReportStatus.COMPLETED);
    assertThat(report.isExpertReviewRecommended()).isFalse();
    assertThat(report.getLimitationsText()).isEqualTo("한계 문구");
    // 리포트는 활동 상태를 건드리지 않는다. 활동은 완료 접수 시점에 이미 COMPLETED 다 —
    //   여기서 다시 전이하면 리포트의 성패가 곧 활동의 성패가 된다(P0-2).
    verify(analysis.getDrawingSession(), never()).completeReporting(any());

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
  void storesVlmDrawnItemsInResponseOrderAndMarksAnExplicitEmptyResultAsPresent() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));
    ObservationGenerationResult result =
        resultWithDrawnItems(
            List.of(
                new DrawnItemDraft("HOUSE", "집"),
                new DrawnItemDraft("HOUSE", "빨간 지붕"),
                new DrawnItemDraft("TREE", "나무"),
                new DrawnItemDraft("PERSON", "웃는 사람")));

    service.complete(context(List.of()), new ObservationGeneration(result, null));

    verify(drawnItemRepository).saveAll(drawnItemsCaptor.capture());
    assertThat(drawnItemsCaptor.getValue())
        .extracting(
            ReportDrawnItem::getDisplayOrder,
            ReportDrawnItem::getDrawingSubject,
            ReportDrawnItem::getName)
        .containsExactly(
            org.assertj.core.groups.Tuple.tuple(0, "HOUSE", "집"),
            org.assertj.core.groups.Tuple.tuple(1, "HOUSE", "빨간 지붕"),
            org.assertj.core.groups.Tuple.tuple(2, "TREE", "나무"),
            org.assertj.core.groups.Tuple.tuple(3, "PERSON", "웃는 사람"));
    assertThat(report.hasDrawnItems()).isTrue();
  }

  @Test
  void discardsInvalidDrawnItemsButKeepsExplicitEmptyResultFromLegacyFallback() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));
    ObservationGenerationResult result =
        resultWithDrawnItems(
            java.util.Arrays.asList(
                new DrawnItemDraft("HOUSE", " "),
                null,
                new DrawnItemDraft("TREE", "가".repeat(21))));

    service.complete(context(List.of()), new ObservationGeneration(result, null));

    verify(drawnItemRepository).saveAll(drawnItemsCaptor.capture());
    assertThat(drawnItemsCaptor.getValue()).isEmpty();
    assertThat(report.hasDrawnItems()).isTrue();
  }

  @Test
  void storesFullReproducibilityTagWithoutTruncation() {
    // S15P11B209-815 회귀: 프롬프트가 report_common + 활동별 변형으로 갈리며 태그가 43자에서 78자로
    // 늘어 VARCHAR(50)을 넘겼고 리포트 저장이 통째로 실패했다. 확장 후에는 원본 그대로 저장돼야 한다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        context(List.of()),
        new ObservationGeneration(resultWithModelVersion(SPLIT_PROMPT_MODEL_VERSION), null));

    assertThat(SPLIT_PROMPT_MODEL_VERSION).hasSize(78);
    assertThat(analysis.getModelVersion()).isEqualTo(SPLIT_PROMPT_MODEL_VERSION);
    verify(observationResultRepository).save(observationCaptor.capture());
    assertThat(observationCaptor.getValue().getGeneratedModelVersion())
        .isEqualTo(SPLIT_PROMPT_MODEL_VERSION);
    verify(conversationSummaryRepository).save(conversationCaptor.capture());
    assertThat(conversationCaptor.getValue().getSummaryModelVersion())
        .isEqualTo(SPLIT_PROMPT_MODEL_VERSION);
    assertThat(report.getStatus()).isEqualTo(ReportStatus.COMPLETED);
  }

  @Test
  void storesModelVersionTruncatedToColumnLimitWhenTagKeepsGrowing() {
    // 프롬프트가 더 갈려 255자를 넘겨도 재현성 태그 하나 때문에 리포트가 실패해선 안 된다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));
    String oversized = "p".repeat(400);

    service.complete(
        context(List.of()), new ObservationGeneration(resultWithModelVersion(oversized), null));

    assertThat(analysis.getModelVersion()).hasSize(255);
    verify(observationResultRepository).save(observationCaptor.capture());
    assertThat(observationCaptor.getValue().getGeneratedModelVersion()).hasSize(255);
    verify(conversationSummaryRepository).save(conversationCaptor.capture());
    assertThat(conversationCaptor.getValue().getSummaryModelVersion()).hasSize(255);
    assertThat(report.getStatus()).isEqualTo(ReportStatus.COMPLETED);
  }

  @Test
  void truncatesAiTextExceedingVarcharColumnLimits() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        context(List.of()), new ObservationGeneration(resultWithOversizedText(), null));

    assertThat(analysis.getModelName()).hasSize(100);
    verify(conversationSummaryRepository).save(conversationCaptor.capture());
    AnalysisConversationSummary summary = conversationCaptor.getValue();
    assertThat(summary.getMainTopic()).hasSize(100);
    assertThat(summary.getExpressedEmotion()).hasSize(50);

    verify(observedFeatureRepository).saveAll(featuresCaptor.capture());
    ReportObservedFeature feature = featuresCaptor.getValue().get(0);
    assertThat(feature.getFeatureCode()).hasSize(80);
    assertThat(feature.getTitle()).hasSize(200);

    verify(guardianQuestionRepository).saveAll(guardianQuestionsCaptor.capture());
    assertThat(guardianQuestionsCaptor.getValue().get(0).getQuestionPurpose()).hasSize(50);

    assertThat(report.getStatus()).isEqualTo(ReportStatus.COMPLETED);
  }

  @Test
  void truncatesEmojiTextOnCharacterCountNotCodeUnitCount() {
    // MySQL VARCHAR(50)은 Emoji도 1자로 센다. Java의 UTF-16 길이로 자르면 25자만 남고
    // Surrogate Pair가 쪼개질 수 있다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        context(List.of()), new ObservationGeneration(resultWithEmotion("😀".repeat(60)), null));

    verify(conversationSummaryRepository).save(conversationCaptor.capture());
    String emotion = conversationCaptor.getValue().getExpressedEmotion();
    assertThat(emotion.codePointCount(0, emotion.length())).isEqualTo(50);
    assertThat(emotion).isEqualTo("😀".repeat(50));
    assertThat(Character.isHighSurrogate(emotion.charAt(emotion.length() - 1))).isFalse();
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

    service.complete(emptyConversationContext(), new ObservationGeneration(validResult(), null));

    verify(eventPublisher, never()).publishEvent(any());
  }

  @Test
  void clampsAiSuppliedReviewedGuardianToExpertOnly() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        emptyConversationContext(),
        new ObservationGeneration(resultWithReviewedGuardianFeature(), null));

    verify(observedFeatureRepository).saveAll(featuresCaptor.capture());
    assertThat(featuresCaptor.getValue())
        .extracting(ReportObservedFeature::getVisibilityScope)
        .containsOnly(ReportFeatureVisibility.EXPERT_ONLY);
  }

  @Test
  void opensReviewedGuardianFeaturesWhenAiSelfReviewPassed() {
    // 이 검증이 없으면 "열리는 경로"를 아무도 확인하지 않는다. 기존 검증은 전부 "닫혀 있는지"만 봤고,
    //   그래서 관찰 특징이 아무에게도 도달하지 않는 상태로 오래 배포돼 있었다(운영 97건 전부 EXPERT_ONLY).
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        emptyConversationContext(),
        new ObservationGeneration(resultWithReviewStatus("AI_REVIEWED"), null));

    verify(observationResultRepository).save(observationCaptor.capture());
    assertThat(observationCaptor.getValue().getReviewStatus())
        .isEqualTo(ObservationReviewStatus.AI_REVIEWED);
    verify(observedFeatureRepository).saveAll(featuresCaptor.capture());
    assertThat(featuresCaptor.getValue())
        .extracting(ReportObservedFeature::getVisibilityScope)
        // AI 가 REVIEWED_GUARDIAN 으로 표시한 것만 열리고 EXPERT_ONLY 표시는 그대로 닫힌다.
        .containsExactly(
            ReportFeatureVisibility.REVIEWED_GUARDIAN, ReportFeatureVisibility.EXPERT_ONLY);
  }

  @Test
  void keepsFeaturesClosedWhenReviewStatusCannotBeInterpreted() {
    // 모르는 상태값을 통과로 취급하면 검토받지 않은 관찰이 보호자에게 열린다. 실패는 닫히는 쪽으로만 기울어야 한다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        emptyConversationContext(),
        new ObservationGeneration(resultWithReviewStatus("EXPERT_APPROVED"), null));

    verify(observationResultRepository).save(observationCaptor.capture());
    assertThat(observationCaptor.getValue().getReviewStatus())
        .isEqualTo(ObservationReviewStatus.AI_DRAFT);
    verify(observedFeatureRepository).saveAll(featuresCaptor.capture());
    assertThat(featuresCaptor.getValue())
        .extracting(ReportObservedFeature::getVisibilityScope)
        .containsOnly(ReportFeatureVisibility.EXPERT_ONLY);
  }

  @Test
  void keepsFeaturesClosedWhenReviewStatusIsMissing() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        emptyConversationContext(), new ObservationGeneration(resultWithReviewStatus(null), null));

    verify(observationResultRepository).save(observationCaptor.capture());
    assertThat(observationCaptor.getValue().getReviewStatus())
        .isEqualTo(ObservationReviewStatus.AI_DRAFT);
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

    service.complete(emptyConversationContext(), new ObservationGeneration(validResult(), null));

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

    service.complete(emptyConversationContext(), new ObservationGeneration(validResult(), null));

    verify(assessment).completeAnalysis(LocalDateTime.now(CLOCK));
    verify(analysis.getDrawingSession(), never()).completeReporting(any());
  }

  @Test
  void completeSkipsWhenAnalysisAlreadySucceeded() {
    DrawingAnalysis analysis = pendingAnalysis();
    analysis.succeedFinal("mock", "1.0", null, LocalDateTime.now(CLOCK));
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));

    service.complete(emptyConversationContext(), new ObservationGeneration(validResult(), null));

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

    service.complete(emptyConversationContext(), new ObservationGeneration(validResult(), null));

    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.PENDING);
    verify(observationResultRepository, never()).save(any());
  }

  @Test
  void completeThrowsWhenAnalysisMissing() {
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.empty());

    assertThatThrownBy(
            () ->
                service.complete(
                    emptyConversationContext(), new ObservationGeneration(validResult(), null)))
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

    assertThatThrownBy(
            () ->
                service.complete(
                    emptyConversationContext(), new ObservationGeneration(validResult(), null)))
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
    // 재시도 판단을 넘기지 않은 호출은 최종 실패로 남는다. 옛 호출부가 어느 쪽인지 모르는 실패를
    //   재시도 대기열에 올려 AI 를 반복 호출하는 것보다, 안 하는 쪽이 안전하다(P0-2).
    assertThat(report.getStatus()).isEqualTo(ReportStatus.FAILED_FINAL);
    assertThat(report.getFailureReason()).isEqualTo("TIMEOUT");
    assertThat(report.getFailedAt()).isEqualTo(LocalDateTime.now(CLOCK));
    // ⚠️ 아이가 한 활동은 실패로 내리지 않는다. 실패한 것은 리포트다. 예전에는 이 호출이
    //    세션을 FAILED 로 만들어 아이 화면에 "활동을 마무리하지 못했어요"가 떴다(2026-08-08 실측).
    verify(analysis.getDrawingSession(), never()).failReporting();
  }

  /** 재시도 가능한 실패는 그 판단을 리포트 상태에 남긴다 (P0-2). */
  @Test
  void marksReportRetryableWhenCallerSaysSo() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.markFailed(ANALYSIS_ID, REPORT_ID, "TIMEOUT", "생성 실패", ReportStatus.FAILED_RETRYABLE);

    assertThat(report.getStatus()).isEqualTo(ReportStatus.FAILED_RETRYABLE);
    assertThat(analysis.getState()).isEqualTo(DrawingAnalysisState.FAILED);
    verify(analysis.getDrawingSession(), never()).failReporting();
  }

  /**
   * 최종 실패는 보호자에게 알린다.
   *
   * <p>아이 화면은 리포트를 기다리지 않고 넘어가므로, 알리지 않으면 실패가 아무 데도 뜨지 않는다.
   */
  @Test
  void publishesFailureEventWhenReportFailsFinally() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.markFailed(ANALYSIS_ID, REPORT_ID, "TIMEOUT", "생성 실패", ReportStatus.FAILED_FINAL);

    verify(eventPublisher).publishEvent(new ReportGenerationFailedEvent(REPORT_ID));
  }

  /**
   * 재시도 가능한 실패는 알리지 않는다.
   *
   * <p>재시도 작업이 되살릴 수 있고 보호자 화면에도 '분석 중'으로 보인다. 알리면 "만들지 못했어요" 뒤에 "완료됐어요"가 따라붙어, 할 일이 없는 보호자에게 불안만
   * 남는다.
   */
  @Test
  void doesNotPublishFailureEventForRetryableFailure() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.markFailed(ANALYSIS_ID, REPORT_ID, "TIMEOUT", "생성 실패", ReportStatus.FAILED_RETRYABLE);

    verify(eventPublisher, never()).publishEvent(any());
  }

  /**
   * 이미 실패로 내려간 리포트를 다시 실패시켜도 두 번 알리지 않는다.
   *
   * <p>보호자에게 같은 실패로 알림이 두 번 가면 리포트가 두 번 실패한 것처럼 보인다. 중복은 GENERATING 필터가 막는다.
   */
  @Test
  void doesNotPublishFailureEventTwiceForSameReport() {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.markFailed(ANALYSIS_ID, REPORT_ID, "TIMEOUT", "생성 실패", ReportStatus.FAILED_FINAL);
    service.markFailed(ANALYSIS_ID, REPORT_ID, "TIMEOUT", "생성 실패", ReportStatus.FAILED_FINAL);

    verify(eventPublisher, org.mockito.Mockito.times(1))
        .publishEvent(new ReportGenerationFailedEvent(REPORT_ID));
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

  @Test
  void sendsOnlyNormalizedDetectionGeometryAndKeepsEveryCode() {
    // AI 는 캔버스 원본 크기를 모르므로 픽셀 좌표로는 용지 점유율을 계산할 수 없다(계약 합의 사항).
    //   픽셀값을 0~1 비율인 척 넘기면 "종이의 대부분을 차지한다" 같은 없는 관찰이 만들어진다.
    givenSingleSessionWithDetections(
        List.of(
            detection(
                910L,
                "HOUSE_DOOR",
                DrawingCoordinateSpace.NORMALIZED,
                "0.100000",
                "0.200000",
                "0.300000",
                "0.400000",
                "0.120000",
                "0.9100"),
            detection(
                911L,
                "HOUSE_ROOF",
                DrawingCoordinateSpace.PIXEL,
                "120.000000",
                "80.000000",
                "300.000000",
                "200.000000",
                null,
                "0.8800")));

    ObservationGenerationContext context = service.loadContext(ANALYSIS_ID).orElseThrow();
    ObservationGenerationContext.SubjectContext subject = context.subjectContexts().getFirst();

    // 코드 목록은 좌표계와 무관하게 전부 담는다 — 관찰 서술의 재료라서다.
    assertThat(subject.detectedObjectCodes()).containsExactly("HOUSE_DOOR", "HOUSE_ROOF");
    // 기하는 정규화 행만 나간다.
    assertThat(subject.detectedObjects())
        .extracting(ObservationGenerationContext.DetectedObjectRef::objectCode)
        .containsExactly("HOUSE_DOOR");
    ObservationGenerationContext.DetectedObjectRef ref = subject.detectedObjects().getFirst();
    assertThat(ref.x()).isEqualByComparingTo("0.100000");
    assertThat(ref.y()).isEqualByComparingTo("0.200000");
    assertThat(ref.width()).isEqualByComparingTo("0.300000");
    assertThat(ref.height()).isEqualByComparingTo("0.400000");
    assertThat(ref.areaRatio()).isEqualByComparingTo("0.120000");
    assertThat(ref.confidence()).isEqualByComparingTo("0.9100");
  }

  @Test
  void sendsEmptyGeometryListWhenEveryDetectionIsPixelOnly() {
    givenSingleSessionWithDetections(
        List.of(
            detection(
                912L,
                "TREE_TRUNK",
                DrawingCoordinateSpace.PIXEL,
                "10.000000",
                "20.000000",
                "30.000000",
                "40.000000",
                null,
                "0.7700")));

    ObservationGenerationContext context = service.loadContext(ANALYSIS_ID).orElseThrow();
    ObservationGenerationContext.SubjectContext subject = context.subjectContexts().getFirst();

    assertThat(subject.detectedObjects()).isEmpty();
    // 기하를 못 보내도 코드 목록은 남아 관찰 서술 재료로 계속 쓰인다.
    assertThat(subject.detectedObjectCodes()).containsExactly("TREE_TRUNK");
  }

  @Test
  void keepsAreaRatioNullInsteadOfDerivingItFromWidthAndHeight() {
    // 🔴 width * height 로 채우면 추정값이 관찰 사실 자리에 들어간다(AI 계약 명시).
    givenSingleSessionWithDetections(
        List.of(
            detection(
                913L,
                "PERSON_FACE",
                DrawingCoordinateSpace.NORMALIZED,
                "0.100000",
                "0.200000",
                "0.300000",
                "0.400000",
                null,
                "0.9000")));

    ObservationGenerationContext context = service.loadContext(ANALYSIS_ID).orElseThrow();

    assertThat(context.subjectContexts().getFirst().detectedObjects().getFirst().areaRatio())
        .isNull();
  }

  @Test
  void dropsNormalizedDetectionThatIsMissingPartOfItsGeometry() {
    // 부분 좌표로는 위치도 크기도 말할 수 없다. 반쪽 기하를 보내느니 그 행을 빼는 편이 옳다.
    givenSingleSessionWithDetections(
        List.of(
            detection(
                914L,
                "HOUSE_WINDOW",
                DrawingCoordinateSpace.NORMALIZED,
                "0.100000",
                "0.200000",
                null,
                "0.400000",
                null,
                "0.9000")));

    ObservationGenerationContext context = service.loadContext(ANALYSIS_ID).orElseThrow();
    ObservationGenerationContext.SubjectContext subject = context.subjectContexts().getFirst();

    assertThat(subject.detectedObjects()).isEmpty();
    assertThat(subject.detectedObjectCodes()).containsExactly("HOUSE_WINDOW");
  }

  /** 단일(비 HTP) 세션 하나에 지정한 탐지 결과만 매달아 loadContext 를 돌릴 수 있게 한다. */
  private void givenSingleSessionWithDetections(List<DrawingDetectedObject> detections) {
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findById(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByAnalysisId(ANALYSIS_ID)).willReturn(Optional.of(report));
    given(htpAssessmentRepository.findStepByDrawingSessionId(DRAWING_SESSION_ID))
        .willReturn(Optional.empty());

    AnalysisObservationResult observation =
        org.mockito.Mockito.mock(AnalysisObservationResult.class);
    DrawingAnalysis detectionAnalysis = org.mockito.Mockito.mock(DrawingAnalysis.class);
    given(observation.getOverallSummary()).willReturn("그림 관찰 서술입니다.");
    given(observation.getAnalysis()).willReturn(detectionAnalysis);
    given(detectionAnalysis.getDetections()).willReturn(detections);
    given(observationResultRepository.findLatestByDrawingSessionId(DRAWING_SESSION_ID))
        .willReturn(Optional.of(observation));
    given(conversationSessionRepository.findByDrawingSessionId(DRAWING_SESSION_ID))
        .willReturn(Optional.empty());
    given(
            emotionRepository.findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
                DRAWING_SESSION_ID))
        .willReturn(List.of());
  }

  private static DrawingDetectedObject detection(
      Long id,
      String label,
      DrawingCoordinateSpace coordinateSpace,
      String x,
      String y,
      String width,
      String height,
      String areaRatio,
      String confidence) {
    DrawingDetectedObject detection = org.mockito.Mockito.mock(DrawingDetectedObject.class);
    lenient().when(detection.getId()).thenReturn(id);
    lenient().when(detection.getLabel()).thenReturn(label);
    lenient().when(detection.getCoordinateSpace()).thenReturn(coordinateSpace);
    lenient().when(detection.getX()).thenReturn(x == null ? null : new BigDecimal(x));
    lenient().when(detection.getY()).thenReturn(y == null ? null : new BigDecimal(y));
    lenient().when(detection.getWidth()).thenReturn(width == null ? null : new BigDecimal(width));
    lenient()
        .when(detection.getHeight())
        .thenReturn(height == null ? null : new BigDecimal(height));
    lenient()
        .when(detection.getAreaRatio())
        .thenReturn(areaRatio == null ? null : new BigDecimal(areaRatio));
    lenient()
        .when(detection.getConfidence())
        .thenReturn(confidence == null ? null : new BigDecimal(confidence));
    return detection;
  }

  @Test
  void savesSubjectReportsInContractOrderWithBeOwnedQaPairsAndSessions() {
    // 875 §5. AI 는 관찰 서술·참조만 보내고 그림과 문답은 BE 가 채운다(941). 두 출처가 주제로 합쳐지는지,
    //   그리고 AI 가 순서를 섞어 보내도 HOUSE→TREE→PERSON 으로 굳는지를 본다 — 순서가 곧 계약이다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        htpContext(),
        new ObservationGeneration(
            resultWithSubjectReports(
                // 일부러 계약 순서와 다르게 보낸다.
                List.of(
                    new ObservationGenerationResult.SubjectReportDraft(
                        "PERSON", List.of("사람을 오른쪽에 그렸어요."), List.of()),
                    new ObservationGenerationResult.SubjectReportDraft(
                        "HOUSE", List.of("집을 가운데 크게 그렸어요.", "창문을 여러 개 그렸어요."), List.of()),
                    new ObservationGenerationResult.SubjectReportDraft(
                        "TREE", List.of("나무를 왼쪽에 그렸어요."), List.of()))),
            null));

    verify(subjectRepository).saveAll(subjectsCaptor.capture());
    List<com.ssafy.b209.report.domain.ReportSubject> subjects = subjectsCaptor.getValue();
    assertThat(subjects)
        .extracting(com.ssafy.b209.report.domain.ReportSubject::getSubjectType)
        .containsExactly("HOUSE", "TREE", "PERSON");
    assertThat(subjects)
        .extracting(com.ssafy.b209.report.domain.ReportSubject::getDisplayOrder)
        .containsExactly(0, 1, 2);
    // 그림 URL 을 발급할 근거인 세션이 주제마다 제자리에 붙어야 한다.
    assertThat(subjects)
        .extracting(com.ssafy.b209.report.domain.ReportSubject::getDrawingSessionId)
        .containsExactly(DRAWING_SESSION_ID, 201L, 202L);

    com.ssafy.b209.report.domain.ReportSubject house = subjects.get(0);
    assertThat(house.getObservations())
        .extracting(com.ssafy.b209.report.domain.ReportSubjectObservation::getObservationText)
        .containsExactly("집을 가운데 크게 그렸어요.", "창문을 여러 개 그렸어요.");
    // 문답은 AI 응답이 아니라 BE 맥락에서 온다 — 아이 발화 원문이 그대로 남는지 본다.
    assertThat(house.getQaPairs())
        .extracting(com.ssafy.b209.report.domain.ReportSubjectQaPair::getQuestionText)
        .containsExactly("집에 누가 살아?");
    assertThat(house.getQaPairs().get(0).getAnswerText()).isEqualTo("우리 가족이요");
    assertThat(house.getQaPairs().get(0).getAnswerState()).isEqualTo("ANSWERED");
    assertThat(house.getQaPairs().get(0).isRepresentative()).isTrue();

    // 답하지 않은 문답은 상태로 구분하고 대표로 올리지 않는다(875 §6).
    com.ssafy.b209.report.domain.ReportSubject tree = subjects.get(1);
    assertThat(tree.getQaPairs().get(0).getAnswerState()).isEqualTo("SKIPPED");
    assertThat(tree.getQaPairs().get(0).getAnswerText()).isNull();
    assertThat(tree.getQaPairs().get(0).isRepresentative()).isFalse();
  }

  @Test
  void linksSubjectInterpretationRefsToPublishedCardsOnly() {
    // 875 §5-1. AI 가 보내는 참조는 자기 응답 배열의 인덱스다. 서버 검증에서 빠진 카드까지 연결하면
    //   보호자 응답에 없는 카드를 가리키게 된다 — 공개된 카드에만 연결되는지 본다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        htpContext(),
        new ObservationGeneration(
            resultWithSubjectReports(
                List.of(
                    new ObservationGenerationResult.SubjectReportDraft(
                        "HOUSE", List.of("집을 크게 그렸어요."), List.of(0, 99)))),
            null));

    verify(subjectRepository).saveAll(subjectsCaptor.capture());
    com.ssafy.b209.report.domain.ReportSubject house = subjectsCaptor.getValue().get(0);
    // 근거를 갖추지 못한 카드는 공개되지 않으므로 참조도 생기지 않는다. 존재하지 않는 인덱스(99)도 버린다.
    assertThat(house.getInterpretations()).isEmpty();
  }

  @Test
  void storesInterpretationsGuidesAndReferencesThroughComplete() {
    // 902 가 만든 저장 메서드가 complete() 에서 호출되지 않아 경향 해석·가이드가 한 건도 저장된 적이
    //   없었다. 저장 메서드 단위 테스트는 이 공백을 잡지 못한다 — 완료 경로가 실제로 부르는지를 본다.
    DrawingAnalysis analysis = pendingAnalysis();
    Report report = generatingReport(analysis);
    given(analysisRepository.findByIdForUpdate(ANALYSIS_ID)).willReturn(Optional.of(analysis));
    given(reportRepository.findByIdForUpdate(REPORT_ID)).willReturn(Optional.of(report));

    service.complete(
        htpContext(), new ObservationGeneration(resultWithSubjectReports(List.of()), null));

    verify(interpretationRepository).saveAll(any());
    verify(evidenceItemRepository).saveAll(any());
    verify(parentGuideRepository).saveAll(any());
    verify(referenceRepository).saveAll(referencesCaptor.capture());
    // 출처 표시는 라이선스 의무(KOGL-1)라 받은 것을 버리지 않는다. 같은 자료는 한 줄로 합친다.
    assertThat(referencesCaptor.getValue())
        .extracting(com.ssafy.b209.report.domain.ReportReference::getTitle)
        .containsExactly("아동 미술 관찰 안내");
    assertThat(referencesCaptor.getValue().get(0).getUrl()).isNull();
  }

  /** HOUSE·TREE·PERSON 세 주제를 담은 생성 맥락이다. 주제마다 세션과 문답이 다르다. */
  private ObservationGenerationContext htpContext() {
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
        List.of(keyLine(0)),
        List.of(
            subjectContext("HOUSE", DRAWING_SESSION_ID, "집에 누가 살아?", "우리 가족이요"),
            subjectContext("TREE", 201L, "이 나무는 어떤 나무야?", null),
            subjectContext("PERSON", 202L, "이 사람은 누구야?", "엄마요")),
        List.of(new ObservationGenerationContext.SelectedEmotionRef(920L, "HAPPY")),
        List.of(
            new ObservationGenerationContext.ActivitySessionRef(DRAWING_SESSION_ID, "HOUSE"),
            new ObservationGenerationContext.ActivitySessionRef(201L, "TREE"),
            new ObservationGenerationContext.ActivitySessionRef(202L, "PERSON")),
        7);
  }

  private ObservationGenerationContext.SubjectContext subjectContext(
      String subject, Long sessionId, String question, String answer) {
    return new ObservationGenerationContext.SubjectContext(
        subject,
        subject + " 관찰 서술",
        List.of(),
        List.of(
            new ObservationGenerationContext.KeyConversationLine(
                1L, question, 2L, answer, "OPTION_ANSWER", false)),
        null,
        List.of(),
        sessionId);
  }

  private ObservationGenerationResult resultWithSubjectReports(
      List<ObservationGenerationResult.SubjectReportDraft> subjectReports) {
    ObservationGenerationResult base = validResult();
    return new ObservationGenerationResult(
        base.requestId(),
        base.modelName(),
        base.modelVersion(),
        base.confidence(),
        base.observationDraft(),
        base.conversationSummary(),
        base.activityNotes(),
        base.followUpGuides(),
        base.guardianQuestions(),
        base.limitationsText(),
        base.drawnItems(),
        List.of(
            new ObservationGenerationResult.PublicInterpretationDraft(
                "RELATIONSHIP",
                "가족과의 연결",
                "가족에게 의지하려는 경향이 보일 수 있습니다.",
                "이번 활동에서 나타난 가능성입니다.",
                "집에서 함께 있는 시간을 살펴봐 주세요.",
                List.of(1L),
                null)),
        List.of(),
        List.of(
            new ObservationGenerationResult.ParentGuideDraft(
                "DRAWING_CONVERSATION", List.of("그림을 함께 보며 이야기해 보세요."))),
        null,
        subjectReports,
        List.of(
            // 같은 자료의 청크 두 건이 하나의 출처로 합쳐지는지 함께 본다.
            new ObservationGenerationResult.RagReferenceDraft("kogl-001", "아동 미술 관찰 안내"),
            new ObservationGenerationResult.RagReferenceDraft("kogl-001#2", "아동 미술 관찰 안내")));
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
        List.of(),
        List.of(new ObservationGenerationContext.SelectedEmotionRef(920L, "HAPPY")),
        List.of(new ObservationGenerationContext.ActivitySessionRef(DRAWING_SESSION_ID, null)),
        7);
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
        List.of(),
        List.of(),
        List.of(new ObservationGenerationContext.ActivitySessionRef(DRAWING_SESSION_ID, null)),
        7);
  }

  private ObservationGenerationContext.KeyConversationLine keyLine(int index) {
    return new ObservationGenerationContext.KeyConversationLine(
        (long) (index + 1),
        "질문 " + index,
        (long) (index + 100),
        "답변 " + index,
        "OPTION_ANSWER",
        false);
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

  private ObservationGenerationResult resultWithCaregiverConnection() {
    ObservationGenerationResult source = validResult();
    DiaryInsightsDraft diary =
        new DiaryInsightsDraft(
            null,
            List.of(),
            List.of(),
            List.of(),
            List.of(
                new DiaryCaregiverQuestionDraft(
                    "그때 네 마음은 어땠어?",
                    "그때 감정을 아이 말로 더 들어보기",
                    "FEELING_SHARING",
                    "아이가 말하면 먼저 마음을 그대로 받아 주세요.",
                    "그때 마음을 색이나 표정으로 같이 그려 볼까요?",
                    List.of())),
            null,
            List.of(),
            List.of(),
            null);
    return new ObservationGenerationResult(
        source.requestId(),
        source.modelName(),
        source.modelVersion(),
        source.confidence(),
        source.observationDraft(),
        source.conversationSummary(),
        source.activityNotes(),
        source.followUpGuides(),
        source.guardianQuestions(),
        source.limitationsText(),
        source.drawnItems(),
        source.publicInterpretations(),
        source.evidenceItems(),
        source.parentGuides(),
        source.crisisAlert(),
        source.subjectReports(),
        source.ragReferences(),
        diary);
  }

  private ObservationGenerationResult resultWithV3DiaryInsights() {
    ObservationGenerationResult source = validResult();
    DiaryEvidenceRefDraft visualRef = new DiaryEvidenceRefDraft("DRAWING_OBSERVATION", "301");
    DiaryInsightsDraft diary =
        new DiaryInsightsDraft(
            null,
            List.of(),
            List.of(),
            List.of(),
            List.of(),
            "아이의 표현을 먼저 그대로 들어 주세요.",
            List.of(),
            List.of(),
            null,
            3,
            new DiaryDataScopeDraft("PARTIAL", "확정된 아이 발화와 그림 관찰을 함께 사용했어요.", 1, 0, 0, 0, 1),
            List.of(
                new DiaryStoryComponentDraft("EVENT", "CONFIRMED", "친구와 놀았어요.", List.of()),
                new DiaryStoryComponentDraft("EMOTION", "UNKNOWN", null, List.of())),
            List.of(
                new DiaryDrawingObservationDraft(
                    "화면 중앙에 두 사람이 나란히 있어요.", "HIGH", true, List.of(visualRef))));
    return new ObservationGenerationResult(
        source.requestId(),
        source.modelName(),
        source.modelVersion(),
        source.confidence(),
        source.observationDraft(),
        source.conversationSummary(),
        source.activityNotes(),
        source.followUpGuides(),
        source.guardianQuestions(),
        source.limitationsText(),
        source.drawnItems(),
        source.publicInterpretations(),
        source.evidenceItems(),
        source.parentGuides(),
        source.crisisAlert(),
        source.subjectReports(),
        source.ragReferences(),
        diary);
  }

  private ObservationGenerationResult resultWithDrawnItems(List<DrawnItemDraft> drawnItems) {
    ObservationGenerationResult source = validResult();
    return new ObservationGenerationResult(
        source.requestId(),
        source.modelName(),
        source.modelVersion(),
        source.confidence(),
        source.observationDraft(),
        source.conversationSummary(),
        source.activityNotes(),
        source.followUpGuides(),
        source.guardianQuestions(),
        source.limitationsText(),
        drawnItems);
  }

  private ObservationGenerationResult resultWithModelVersion(String modelVersion) {
    return new ObservationGenerationResult(
        "request-1",
        "mock-observation-generator",
        modelVersion,
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
            List.of()),
        new ConversationSummaryDraft("보호자용 대화 요약", "오늘의 그림", "즐거움", "SELECTED", "즐거웠어요"),
        List.of(),
        List.of(),
        List.of(),
        "한계 문구");
  }

  private ObservationGenerationResult resultWithOversizedText() {
    return new ObservationGenerationResult(
        "request-1",
        "모".repeat(150),
        SPLIT_PROMPT_MODEL_VERSION,
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
                new ObservedFeatureDraft(
                    "코".repeat(120), "제".repeat(300), "적극적으로 표현", "관찰 근거", "EXPERT_ONLY"))),
        new ConversationSummaryDraft(
            "보호자용 대화 요약", "주".repeat(150), "감".repeat(90), "SELECTED", "즐거웠어요"),
        List.of(),
        List.of(),
        List.of(new GuardianQuestionDraft("어떤 기분이었어?", "목".repeat(90))),
        "한계 문구");
  }

  private ObservationGenerationResult resultWithEmotion(String expressedEmotion) {
    return new ObservationGenerationResult(
        "request-1",
        "mock-observation-generator",
        SPLIT_PROMPT_MODEL_VERSION,
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
            List.of()),
        new ConversationSummaryDraft("보호자용 대화 요약", "오늘의 그림", expressedEmotion, "SELECTED", null),
        List.of(),
        List.of(),
        List.of(),
        "한계 문구");
  }

  /** 검토 상태만 바꾼 결과다. 관찰 특징은 {@code REVIEWED_GUARDIAN} 한 건 + {@code EXPERT_ONLY} 한 건으로 고정한다. */
  private ObservationGenerationResult resultWithReviewStatus(String reviewStatus) {
    ObservationGenerationResult source = validResult();
    ObservationDraft draft = source.observationDraft();
    return new ObservationGenerationResult(
        source.requestId(),
        source.modelName(),
        source.modelVersion(),
        source.confidence(),
        new ObservationDraft(
            reviewStatus,
            draft.overallSummary(),
            draft.positiveSignals(),
            draft.attentionPoints(),
            draft.evidenceSummary(),
            draft.guardianGuidance(),
            draft.followUpQuestion(),
            draft.expertReviewRequired(),
            draft.disclaimer(),
            draft.features()),
        source.conversationSummary(),
        source.activityNotes(),
        source.followUpGuides(),
        source.guardianQuestions(),
        source.limitationsText());
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
