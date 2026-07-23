package com.ssafy.b209.report.service;

import com.ssafy.b209.analysis.domain.AnalysisConversationSummary;
import com.ssafy.b209.analysis.domain.AnalysisObservationResult;
import com.ssafy.b209.analysis.domain.ConversationEmotionSource;
import com.ssafy.b209.analysis.domain.DrawingAnalysis;
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
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.global.exception.BusinessException;
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
import java.util.List;
import java.util.Optional;
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

    ConversationSession conversation =
        conversationSessionRepository.findByDrawingSessionId(drawingSessionId).orElse(null);
    Long conversationSessionId = conversation == null ? null : conversation.getId();
    String questionDifficulty = conversation == null ? null : conversation.getDifficultySnapshot();

    int questionCount = 0;
    int answeredCount = 0;
    int skippedCount = 0;
    int unrecognizedSpeechCount = 0;
    List<ObservationGenerationContext.KeyConversationLine> keyConversations = new ArrayList<>();
    if (conversationSessionId != null) {
      questionCount = (int) conversationMessageRepository.countQuestions(conversationSessionId);
      answeredCount = (int) conversationMessageRepository.countAnswered(conversationSessionId);
      skippedCount = (int) conversationMessageRepository.countSkipped(conversationSessionId);
      unrecognizedSpeechCount =
          (int) conversationMessageRepository.countUnrecognizedSpeech(conversationSessionId);
      List<KeyConversationSource> sources =
          conversationMessageRepository.findKeyConversationSources(conversationSessionId);
      for (KeyConversationSource source : sources) {
        if (keyConversations.size() >= MAX_KEY_CONVERSATIONS) {
          break;
        }
        keyConversations.add(
            new ObservationGenerationContext.KeyConversationLine(
                source.getQuestionMessageId(),
                source.getQuestionText(),
                source.getAnswerMessageId(),
                source.getAnswerText(),
                source.getAnswerType()));
      }
    }

    List<String> selectedEmotions =
        emotionRepository
            .findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(drawingSessionId)
            .stream()
            .map(DrawingSessionEmotion::getEmotionCode)
            .map(Enum::name)
            .toList();

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
            keyConversations));
  }

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
      analysis.succeedFinal(result.modelName(), result.modelVersion(), result.confidence(), now);

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
              result.modelVersion(),
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
              summary == null ? null : summary.mainTopic(),
              summary == null ? null : summary.expressedEmotion(),
              summary == null ? null : parseEmotionSource(summary.emotionSource()),
              context.questionCount(),
              context.answeredCount(),
              context.skippedCount(),
              context.unrecognizedSpeechCount(),
              summary == null ? null : summary.representativeUtterance(),
              result.modelVersion(),
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
      analysis.getDrawingSession().completeReporting(now);
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
              analysis.failFinal(failureCode, failureMessage, now);
              analysis.getDrawingSession().failReporting();
            });
    if (reportId != null) {
      reportRepository
          .findByIdForUpdate(reportId)
          .filter(report -> report.getStatus() == ReportStatus.GENERATING)
          .ifPresent(report -> report.fail(FAILED_LIMITATIONS, now));
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
              feature.featureCode(),
              feature.title(),
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
              report, question.questionText(), question.questionPurpose(), index));
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
