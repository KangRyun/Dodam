package com.ssafy.b209.report.service;

import com.ssafy.b209.analysis.domain.AnalysisConversationSummary;
import com.ssafy.b209.analysis.domain.AnalysisObservationResult;
import com.ssafy.b209.analysis.domain.ConversationEmotionSource;
import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.domain.ObservationReviewStatus;
import com.ssafy.b209.analysis.repository.AnalysisConversationSummaryRepository;
import com.ssafy.b209.analysis.repository.AnalysisObservationResultRepository;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.dto.KeyConversationSource;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.support.ColumnTextLimiter;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportActivityNote;
import com.ssafy.b209.report.domain.ReportActivitySummary;
import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import com.ssafy.b209.report.domain.ReportFollowUpGuide;
import com.ssafy.b209.report.domain.ReportGuardianQuestion;
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
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 관찰 리포트 생성 결과를 정규화 테이블에 저장하고 분석·리포트·그림 활동 세션 상태를 전이한다.
 *
 * <p>AI Client 호출은 이 클래스 밖에서 수행하며, 저장은 하나의 Transaction에서 전부 반영하거나 실패 시 전체 Rollback한다. 이미 완료된 대상은
 * 재생성 없이 종료해 멱등성을 보장한다.
 */
@Service
public class ObservationReportPersistenceService {

  private static final int MAX_KEY_CONVERSATIONS = 5;
  private static final String FAILED_LIMITATIONS = "리포트 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.";

  // AI 응답이 들어가는 VARCHAR 컬럼의 문자 수 상한이다. 값 하나가 상한을 넘겨도 리포트 전체가 실패하지 않도록
  // 저장 직전에 ColumnTextLimiter로 맞춘다(S15P11B209-815). TEXT 컬럼은 상한이 없어 대상이 아니다.
  private static final int MODEL_NAME_LIMIT = 100;
  private static final int MODEL_VERSION_LIMIT = 255;
  private static final int MAIN_TOPIC_LIMIT = 100;
  private static final int EXPRESSED_EMOTION_LIMIT = 50;
  private static final int FEATURE_CODE_LIMIT = 80;
  private static final int FEATURE_TITLE_LIMIT = 200;
  private static final int QUESTION_PURPOSE_LIMIT = 50;
  private static final int ANALYSIS_ERROR_CODE_LIMIT = 80;
  private static final int REPORT_FAILURE_REASON_LIMIT = 100;

  private final DrawingAnalysisRepository analysisRepository;
  private final ReportRepository reportRepository;
  private final AnalysisObservationResultRepository observationResultRepository;
  private final AnalysisConversationSummaryRepository conversationSummaryRepository;
  private final ReportActivitySummaryRepository activitySummaryRepository;
  private final ReportActivityNoteRepository activityNoteRepository;
  private final ReportObservedFeatureRepository observedFeatureRepository;
  private final ReportKeyConversationRepository keyConversationRepository;
  private final ReportFollowUpGuideRepository followUpGuideRepository;
  private final ReportGuardianQuestionRepository guardianQuestionRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationMessageRepository conversationMessageRepository;
  private final DrawingSessionEmotionRepository emotionRepository;
  private final HtpAssessmentRepository htpAssessmentRepository;
  private final ApplicationEventPublisher eventPublisher;
  private final Clock clock;

  /**
   * 관찰 리포트 저장에 필요한 저장소와 UTC 시계를 주입받는다.
   *
   * @param analysisRepository 최종 분석 저장소
   * @param reportRepository 리포트 저장소
   * @param observationResultRepository 관찰 결과 저장소
   * @param conversationSummaryRepository 대화 요약 저장소
   * @param activitySummaryRepository 리포트 활동 요약 저장소
   * @param activityNoteRepository 리포트 활동 주의사항 저장소
   * @param observedFeatureRepository 리포트 관찰 특징 저장소
   * @param keyConversationRepository 리포트 주요 대화 저장소
   * @param followUpGuideRepository 리포트 후속 안내 저장소
   * @param guardianQuestionRepository 리포트 보호자 질문 저장소
   * @param conversationSessionRepository 대화 세션 저장소
   * @param conversationMessageRepository 대화 메시지 집계 저장소
   * @param emotionRepository 그림 활동 선택 감정 저장소
   * @param htpAssessmentRepository HTP 묶음의 세 세션 집계와 상태 전이 저장소
   * @param eventPublisher 완료 커밋 후 분석 완료 알림을 요청할 이벤트 발행기
   * @param clock 저장 시각을 제공하는 UTC 시계
   */
  public ObservationReportPersistenceService(
      DrawingAnalysisRepository analysisRepository,
      ReportRepository reportRepository,
      AnalysisObservationResultRepository observationResultRepository,
      AnalysisConversationSummaryRepository conversationSummaryRepository,
      ReportActivitySummaryRepository activitySummaryRepository,
      ReportActivityNoteRepository activityNoteRepository,
      ReportObservedFeatureRepository observedFeatureRepository,
      ReportKeyConversationRepository keyConversationRepository,
      ReportFollowUpGuideRepository followUpGuideRepository,
      ReportGuardianQuestionRepository guardianQuestionRepository,
      ConversationSessionRepository conversationSessionRepository,
      ConversationMessageRepository conversationMessageRepository,
      DrawingSessionEmotionRepository emotionRepository,
      HtpAssessmentRepository htpAssessmentRepository,
      ApplicationEventPublisher eventPublisher,
      Clock clock) {
    this.analysisRepository = analysisRepository;
    this.reportRepository = reportRepository;
    this.observationResultRepository = observationResultRepository;
    this.conversationSummaryRepository = conversationSummaryRepository;
    this.activitySummaryRepository = activitySummaryRepository;
    this.activityNoteRepository = activityNoteRepository;
    this.observedFeatureRepository = observedFeatureRepository;
    this.keyConversationRepository = keyConversationRepository;
    this.followUpGuideRepository = followUpGuideRepository;
    this.guardianQuestionRepository = guardianQuestionRepository;
    this.conversationSessionRepository = conversationSessionRepository;
    this.conversationMessageRepository = conversationMessageRepository;
    this.emotionRepository = emotionRepository;
    this.htpAssessmentRepository = htpAssessmentRepository;
    this.eventPublisher = eventPublisher;
    this.clock = clock;
  }

  /**
   * 생성 대상 분석과 리포트가 처리 가능한 상태이면 저장에 필요한 맥락을 조회한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 처리 가능한 경우의 생성 맥락, 대상이 없거나 이미 완료됐으면 빈 값
   */
  @Transactional(readOnly = true, propagation = Propagation.REQUIRES_NEW)
  public Optional<ObservationGenerationContext> loadContext(Long analysisId) {
    Optional<DrawingAnalysis> analysisOptional = analysisRepository.findById(analysisId);
    if (analysisOptional.isEmpty()) {
      return Optional.empty();
    }
    DrawingAnalysis analysis = analysisOptional.get();
    if (!analysis.isPending()) {
      return Optional.empty();
    }
    Optional<Report> reportOptional = reportRepository.findByAnalysisId(analysisId);
    if (reportOptional.isEmpty() || reportOptional.get().getStatus() != ReportStatus.GENERATING) {
      return Optional.empty();
    }
    DrawingSession session = analysis.getDrawingSession();
    Long drawingSessionId = session.getId();
    String expressedEmotionText = session.getExpressedEmotionText();
    // HTP면 (세션, 주제) 3쌍 — 주제별 서술·문답 수집(S15P11B209-741)에 주제가 필요하다.
    // 그림일기·단독 세션은 주제 없는 1쌍.
    List<SubjectSessionRef> contextSessions =
        htpAssessmentRepository
            .findStepByDrawingSessionId(drawingSessionId)
            .map(
                step ->
                    step.getAssessment().getSteps().stream()
                        .sorted(Comparator.comparingInt(HtpAssessmentStep::getStepOrder))
                        .map(
                            htpStep ->
                                new SubjectSessionRef(
                                    htpStep.getDrawingSession().getId(),
                                    htpStep.getDrawingSubject().name()))
                        .toList())
            .orElseGet(() -> List.of(new SubjectSessionRef(drawingSessionId, null)));
    List<Long> contextSessionIds =
        contextSessions.stream().map(SubjectSessionRef::drawingSessionId).toList();

    ConversationSession representativeConversation =
        conversationSessionRepository.findByDrawingSessionId(drawingSessionId).orElse(null);
    Long conversationSessionId =
        representativeConversation == null ? null : representativeConversation.getId();
    String questionDifficulty =
        representativeConversation == null
            ? null
            : representativeConversation.getDifficultySnapshot();

    int questionCount = 0;
    int answeredCount = 0;
    int skippedCount = 0;
    int unrecognizedSpeechCount = 0;
    List<ObservationGenerationContext.KeyConversationLine> keyConversations = new ArrayList<>();
    List<ObservationGenerationContext.SubjectContext> subjectContexts = new ArrayList<>();
    for (SubjectSessionRef contextSession : contextSessions) {
      Long contextSessionId = contextSession.drawingSessionId();
      // 주제별 문답(S15P11B209-741) — keyConversations(리포트 저장용 평탄 목록)와 같은 소스를
      // 쓰되, MAX_KEY_CONVERSATIONS 상한과 무관하게 주제 단위로 담는다(상한에 걸리면 뒤 주제의
      // 문답이 통째로 빠져 리포트가 특정 그림에만 치우친다).
      List<ObservationGenerationContext.KeyConversationLine> subjectQaPairs = new ArrayList<>();
      ConversationSession conversation =
          conversationSessionRepository.findByDrawingSessionId(contextSessionId).orElse(null);
      if (conversation != null) {
        Long contextConversationId = conversation.getId();
        questionCount += (int) conversationMessageRepository.countQuestions(contextConversationId);
        answeredCount += (int) conversationMessageRepository.countAnswered(contextConversationId);
        skippedCount += (int) conversationMessageRepository.countSkipped(contextConversationId);
        unrecognizedSpeechCount +=
            (int) conversationMessageRepository.countUnrecognizedSpeech(contextConversationId);
        List<KeyConversationSource> sources =
            conversationMessageRepository.findKeyConversationSources(contextConversationId);
        for (KeyConversationSource source : sources) {
          ObservationGenerationContext.KeyConversationLine line =
              new ObservationGenerationContext.KeyConversationLine(
                  source.getQuestionMessageId(),
                  source.getQuestionText(),
                  source.getAnswerMessageId(),
                  source.getAnswerText(),
                  source.getAnswerType());
          subjectQaPairs.add(line);
          if (keyConversations.size() < MAX_KEY_CONVERSATIONS) {
            keyConversations.add(line);
          }
        }
      }

      // 주제별 그림 서술·탐지 코드 — 대화를 건너뛴 세션도 그림 자체는 리포트 근거가 된다.
      AnalysisObservationResult subjectObservation =
          observationResultRepository.findLatestByDrawingSessionId(contextSessionId).orElse(null);
      String drawingDescription =
          subjectObservation == null ? null : subjectObservation.getOverallSummary();
      List<String> detectedObjectCodes =
          subjectObservation == null
              ? List.of()
              : subjectObservation.getAnalysis().getDetections().stream()
                  .map(DrawingDetectedObject::getLabel)
                  .toList();
      // 서술·코드·문답이 전부 비면 담지 않는다 — 빈 항목은 AI 프롬프트에 노이즈만 더한다.
      if (drawingDescription != null
          || !detectedObjectCodes.isEmpty()
          || !subjectQaPairs.isEmpty()) {
        subjectContexts.add(
            new ObservationGenerationContext.SubjectContext(
                contextSession.drawingSubject(),
                drawingDescription,
                detectedObjectCodes,
                subjectQaPairs));
      }
    }

    List<DrawingSessionEmotion> emotionSources =
        contextSessionIds.size() == 1
            ? emotionRepository.findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
                drawingSessionId)
            : emotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
                    contextSessionIds);
    List<String> selectedEmotions =
        emotionSources.stream().map(DrawingSessionEmotion::getEmotionCode).map(Enum::name).toList();

    return Optional.of(
        new ObservationGenerationContext(
            analysisId,
            drawingSessionId,
            reportOptional.get().getId(),
            conversationSessionId,
            questionDifficulty,
            questionCount,
            answeredCount,
            skippedCount,
            unrecognizedSpeechCount,
            selectedEmotions,
            expressedEmotionText,
            keyConversations,
            subjectContexts));
  }

  /** 주제별 수집 대상 세션과 HTP 주제의 쌍이다 (S15P11B209-741). 그림일기·단독 세션은 주제가 {@code null}. */
  private record SubjectSessionRef(Long drawingSessionId, String drawingSubject) {}

  /**
   * 검증된 관찰 결과를 정규화 테이블에 저장하고 분석·리포트·그림 활동 세션을 완료 상태로 전이한다.
   *
   * @param context 생성 맥락
   * @param result AI Client가 반환한 관찰 리포트 결과
   * @throws BusinessException 대상이 사라졌거나 저장 충돌이 발생한 경우
   * @throws IllegalStateException 그림 활동 세션이 REPORTING 중인 진행 상태가 아닌 경우
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void complete(ObservationGenerationContext context, ObservationGenerationResult result) {
    DrawingAnalysis analysis =
        analysisRepository
            .findByIdForUpdate(context.analysisId())
            .orElseThrow(
                () -> new BusinessException(MockObservationReportErrorCode.ANALYSIS_NOT_FOUND));
    if (!analysis.isPending()) {
      return;
    }
    Report report =
        reportRepository
            .findByIdForUpdate(context.reportId())
            .orElseThrow(
                () -> new BusinessException(MockObservationReportErrorCode.REPORT_NOT_FOUND));
    if (report.getStatus() != ReportStatus.GENERATING) {
      return;
    }
    LocalDateTime now = LocalDateTime.now(clock);
    ObservationDraft draft = result.observationDraft();
    ConversationSummaryDraft summary = result.conversationSummary();

    try {
      analysis.succeedFinal(
          ColumnTextLimiter.fit(result.modelName(), MODEL_NAME_LIMIT, "analyses.model_name"),
          ColumnTextLimiter.fit(
              result.modelVersion(), MODEL_VERSION_LIMIT, "analyses.model_version"),
          result.confidence(),
          now);

      AnalysisObservationResult observation =
          AnalysisObservationResult.aiDraft(
              analysis,
              1,
              draft.overallSummary(),
              draft.positiveSignals(),
              draft.attentionPoints(),
              draft.evidenceSummary(),
              draft.guardianGuidance(),
              draft.followUpQuestion(),
              draft.expertReviewRequired(),
              draft.disclaimer(),
              ColumnTextLimiter.fit(
                  result.modelVersion(),
                  MODEL_VERSION_LIMIT,
                  "analysis_observation_results.generated_model_version"),
              now);
      observationResultRepository.save(observation);

      ConversationSession conversation =
          context.conversationSessionId() == null
              ? null
              : conversationSessionRepository
                  .findById(context.conversationSessionId())
                  .orElse(null);
      conversationSummaryRepository.save(
          AnalysisConversationSummary.create(
              analysis,
              conversation,
              summary == null ? null : summary.summaryText(),
              summary == null
                  ? null
                  : ColumnTextLimiter.fit(
                      summary.mainTopic(),
                      MAIN_TOPIC_LIMIT,
                      "analysis_conversation_summaries.main_topic"),
              summary == null
                  ? null
                  : ColumnTextLimiter.fit(
                      summary.expressedEmotion(),
                      EXPRESSED_EMOTION_LIMIT,
                      "analysis_conversation_summaries.expressed_emotion"),
              summary == null ? null : parseEmotionSource(summary.emotionSource()),
              context.questionCount(),
              context.answeredCount(),
              context.skippedCount(),
              context.unrecognizedSpeechCount(),
              summary == null ? null : summary.representativeUtterance(),
              ColumnTextLimiter.fit(
                  result.modelVersion(),
                  MODEL_VERSION_LIMIT,
                  "analysis_conversation_summaries.summary_model_version"),
              now));

      activitySummaryRepository.save(
          ReportActivitySummary.create(
              report,
              null,
              null,
              null,
              false,
              context.questionCount(),
              context.answeredCount(),
              context.skippedCount(),
              summary == null ? null : summary.summaryText()));

      boolean expertReviewed = observation.getReviewStatus() != ObservationReviewStatus.AI_DRAFT;
      saveActivityNotes(report, safeList(result.activityNotes()));
      saveObservedFeatures(report, draft.features(), expertReviewed);
      saveKeyConversations(report, context.keyConversations());
      saveFollowUpGuides(report, safeList(result.followUpGuides()));
      saveGuardianQuestions(report, safeList(result.guardianQuestions()));

      report.complete(draft.expertReviewRequired(), result.limitationsText(), now);
      Optional<HtpAssessment> htpAssessment =
          htpAssessmentRepository.findByStepDrawingSessionIdForUpdate(
              analysis.getDrawingSession().getId());
      if (htpAssessment.isPresent()) {
        htpAssessment.get().completeAnalysis(now);
      } else {
        analysis.getDrawingSession().completeReporting(now);
      }
      eventPublisher.publishEvent(new AnalysisCompletedEvent(context.reportId()));
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(
          MockObservationReportErrorCode.REPORT_STORAGE_CONFLICT, exception);
    }
  }

  /**
   * 생성 또는 저장 실패를 대기 중 분석과 생성 중 리포트에 기록한다.
   *
   * @param analysisId 최종 분석 식별자
   * @param reportId 리포트 식별자이며 없으면 {@code null}
   * @param failureCode 원문을 포함하지 않는 실패 분류 코드
   * @param failureMessage 외부에 노출해도 되는 안전한 실패 메시지
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void markFailed(
      Long analysisId, Long reportId, String failureCode, String failureMessage) {
    LocalDateTime now = LocalDateTime.now(clock);
    analysisRepository
        .findByIdForUpdate(analysisId)
        .filter(DrawingAnalysis::isPending)
        .ifPresent(
            analysis -> {
              analysis.failFinal(
                  ColumnTextLimiter.fit(
                      failureCode, ANALYSIS_ERROR_CODE_LIMIT, "analyses.error_code"),
                  failureMessage,
                  now);
              Optional<HtpAssessment> htpAssessment =
                  htpAssessmentRepository.findByStepDrawingSessionIdForUpdate(
                      analysis.getDrawingSession().getId());
              if (htpAssessment.isPresent()) {
                htpAssessment.get().failAnalysis();
              } else {
                analysis.getDrawingSession().failReporting();
              }
            });
    if (reportId != null) {
      reportRepository
          .findByIdForUpdate(reportId)
          .filter(report -> report.getStatus() == ReportStatus.GENERATING)
          .ifPresent(
              report ->
                  report.fail(
                      FAILED_LIMITATIONS,
                      ColumnTextLimiter.fit(
                          failureCode, REPORT_FAILURE_REASON_LIMIT, "reports.failure_reason"),
                      now));
    }
  }

  private void saveActivityNotes(Report report, List<String> notes) {
    List<ReportActivityNote> entities = new ArrayList<>();
    for (int index = 0; index < notes.size(); index++) {
      String note = notes.get(index);
      if (note != null && !note.isBlank()) {
        entities.add(ReportActivityNote.create(report, note, index));
      }
    }
    activityNoteRepository.saveAll(entities);
  }

  private void saveObservedFeatures(
      Report report, List<ObservedFeatureDraft> features, boolean expertReviewed) {
    List<ReportObservedFeature> entities = new ArrayList<>();
    List<ObservedFeatureDraft> source = safeList(features);
    for (int index = 0; index < source.size(); index++) {
      ObservedFeatureDraft feature = source.get(index);
      entities.add(
          ReportObservedFeature.create(
              report,
              ColumnTextLimiter.fit(
                  feature.featureCode(),
                  FEATURE_CODE_LIMIT,
                  "report_observed_features.feature_code"),
              ColumnTextLimiter.fit(
                  feature.title(), FEATURE_TITLE_LIMIT, "report_observed_features.title"),
              feature.description(),
              feature.evidenceSummary(),
              resolveVisibility(feature.visibilityScope(), expertReviewed),
              index));
    }
    observedFeatureRepository.saveAll(entities);
  }

  private void saveKeyConversations(
      Report report, List<ObservationGenerationContext.KeyConversationLine> lines) {
    List<ReportKeyConversation> entities = new ArrayList<>();
    for (int index = 0; index < lines.size(); index++) {
      ObservationGenerationContext.KeyConversationLine line = lines.get(index);
      entities.add(
          ReportKeyConversation.create(
              report,
              line.questionMessageId(),
              line.answerMessageId(),
              line.questionText(),
              line.answerText(),
              line.answerType(),
              index));
    }
    keyConversationRepository.saveAll(entities);
  }

  private void saveFollowUpGuides(Report report, List<FollowUpGuideDraft> guides) {
    List<ReportFollowUpGuide> entities = new ArrayList<>();
    for (int index = 0; index < guides.size(); index++) {
      FollowUpGuideDraft guide = guides.get(index);
      entities.add(ReportFollowUpGuide.create(report, guide.guidance(), guide.detailText(), index));
    }
    followUpGuideRepository.saveAll(entities);
  }

  private void saveGuardianQuestions(Report report, List<GuardianQuestionDraft> questions) {
    List<ReportGuardianQuestion> entities = new ArrayList<>();
    for (int index = 0; index < questions.size(); index++) {
      GuardianQuestionDraft question = questions.get(index);
      entities.add(
          ReportGuardianQuestion.create(
              report,
              question.questionText(),
              ColumnTextLimiter.fit(
                  question.questionPurpose(),
                  QUESTION_PURPOSE_LIMIT,
                  "report_guardian_questions.question_purpose"),
              index));
    }
    guardianQuestionRepository.saveAll(entities);
  }

  private static ReportFeatureVisibility resolveVisibility(String value, boolean expertReviewed) {
    if (expertReviewed && "REVIEWED_GUARDIAN".equals(value)) {
      return ReportFeatureVisibility.REVIEWED_GUARDIAN;
    }
    return ReportFeatureVisibility.EXPERT_ONLY;
  }

  private static ConversationEmotionSource parseEmotionSource(String value) {
    if (value == null) {
      return null;
    }
    try {
      return ConversationEmotionSource.valueOf(value);
    } catch (IllegalArgumentException exception) {
      return null;
    }
  }

  private static <T> List<T> safeList(List<T> value) {
    return value == null ? List.of() : value;
  }
}
