package com.ssafy.b209.report.service;

import com.ssafy.b209.analysis.domain.AnalysisConversationSummary;
import com.ssafy.b209.analysis.domain.AnalysisObservationResult;
import com.ssafy.b209.analysis.domain.ConversationEmotionSource;
import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingCoordinateSpace;
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
import com.ssafy.b209.drawing.service.StrokeBehaviorSummary;
import com.ssafy.b209.drawing.service.StrokeBehaviorSummaryService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.support.ColumnTextLimiter;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportActivityNote;
import com.ssafy.b209.report.domain.ReportActivitySummary;
import com.ssafy.b209.report.domain.ReportCrisisAlert;
import com.ssafy.b209.report.domain.ReportDrawnItem;
import com.ssafy.b209.report.domain.ReportEvidenceItem;
import com.ssafy.b209.report.domain.ReportEvidenceSourceKind;
import com.ssafy.b209.report.domain.ReportEvidenceSourceRef;
import com.ssafy.b209.report.domain.ReportEvidenceSourceType;
import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import com.ssafy.b209.report.domain.ReportFollowUpGuide;
import com.ssafy.b209.report.domain.ReportGuardianQuestion;
import com.ssafy.b209.report.domain.ReportInterpretationCategory;
import com.ssafy.b209.report.domain.ReportInterpretationDisclosureState;
import com.ssafy.b209.report.domain.ReportKeyConversation;
import com.ssafy.b209.report.domain.ReportObservedFeature;
import com.ssafy.b209.report.domain.ReportParentGuide;
import com.ssafy.b209.report.domain.ReportParentGuideType;
import com.ssafy.b209.report.domain.ReportPublicInterpretation;
import com.ssafy.b209.report.domain.ReportReference;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.domain.ReportSubject;
import com.ssafy.b209.report.domain.ReportSubjectQaPair;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ConversationSummaryDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.DrawnItemDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.FollowUpGuideDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.GuardianQuestionDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservationDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservedFeatureDraft;
import com.ssafy.b209.report.exception.MockObservationReportErrorCode;
import com.ssafy.b209.report.repository.ReportActivityNoteRepository;
import com.ssafy.b209.report.repository.ReportActivitySummaryRepository;
import com.ssafy.b209.report.repository.ReportCrisisAlertRepository;
import com.ssafy.b209.report.repository.ReportDrawnItemRepository;
import com.ssafy.b209.report.repository.ReportEvidenceItemRepository;
import com.ssafy.b209.report.repository.ReportFollowUpGuideRepository;
import com.ssafy.b209.report.repository.ReportGuardianQuestionRepository;
import com.ssafy.b209.report.repository.ReportKeyConversationRepository;
import com.ssafy.b209.report.repository.ReportObservedFeatureRepository;
import com.ssafy.b209.report.repository.ReportParentGuideRepository;
import com.ssafy.b209.report.repository.ReportPublicInterpretationRepository;
import com.ssafy.b209.report.repository.ReportReferenceRepository;
import com.ssafy.b209.report.repository.ReportRepository;
import com.ssafy.b209.report.repository.ReportSubjectRepository;
import com.ssafy.b209.report.safety.InterpretationCandidate;
import com.ssafy.b209.report.safety.InterpretationSafetyOutcome;
import com.ssafy.b209.report.safety.InterpretationSafetyVerifier;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

  private static final Logger log =
      LoggerFactory.getLogger(ObservationReportPersistenceService.class);

  private static final int MAX_KEY_CONVERSATIONS = 5;

  /** 화면이 먼저 펼치는 대표 문답 수다 (875 §6). 나머지는 "대화 더 보기"로 접힌다. */
  private static final int MAX_REPRESENTATIVE_QA_PAIRS = 3;

  /** 875 §5 가 보장하는 주제 노출 순서다. 순서가 곧 계약이라 상수로 고정한다. */
  private static final List<String> SUBJECT_ORDER = List.of("HOUSE", "TREE", "PERSON");

  private static final String FAILED_LIMITATIONS = "리포트 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.";

  // AI 응답이 들어가는 VARCHAR 컬럼의 문자 수 상한이다. 값 하나가 상한을 넘겨도 리포트 전체가 실패하지 않도록
  private static final int EVIDENCE_TEXT_LIMIT = 1000;
  private static final int INTERPRETATION_TITLE_LIMIT = 200;
  private static final int CRISIS_TITLE_LIMIT = 200;
  private static final int CRISIS_RESOURCE_NAME_LIMIT = 100;
  private static final int CRISIS_CONTACT_LIMIT = 100;
  private static final int CRISIS_NOTE_LIMIT = 300;

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
  private final ReportDrawnItemRepository drawnItemRepository;
  private final ReportPublicInterpretationRepository interpretationRepository;
  private final ReportEvidenceItemRepository evidenceItemRepository;
  private final ReportParentGuideRepository parentGuideRepository;
  private final ReportCrisisAlertRepository crisisAlertRepository;
  private final ReportSubjectRepository subjectRepository;
  private final ReportReferenceRepository referenceRepository;
  private final InterpretationSafetyVerifier safetyVerifier;
  private final InterpretationCandidateAdapter candidateAdapter;
  private final ReportObservedFeatureRepository observedFeatureRepository;
  private final ReportKeyConversationRepository keyConversationRepository;
  private final ReportFollowUpGuideRepository followUpGuideRepository;
  private final ReportGuardianQuestionRepository guardianQuestionRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationMessageRepository conversationMessageRepository;
  private final DrawingSessionEmotionRepository emotionRepository;
  private final HtpAssessmentRepository htpAssessmentRepository;
  private final StrokeBehaviorSummaryService behaviorSummaryService;
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
   * @param drawnItemRepository 리포트 '그린 것' 저장소
   * @param interpretationRepository 경향 해석 저장소
   * @param evidenceItemRepository 경향 해석 근거 저장소
   * @param parentGuideRepository 보호자 가이드 저장소
   * @param crisisAlertRepository 위기 대응 안내 저장소
   * @param safetyVerifier 경향 해석 2단 안전 검증기
   * @param candidateAdapter AI 응답을 검증기 입력으로 옮기는 Adapter
   * @param observedFeatureRepository 리포트 관찰 특징 저장소
   * @param keyConversationRepository 리포트 주요 대화 저장소
   * @param followUpGuideRepository 리포트 후속 안내 저장소
   * @param guardianQuestionRepository 리포트 보호자 질문 저장소
   * @param conversationSessionRepository 대화 세션 저장소
   * @param conversationMessageRepository 대화 메시지 집계 저장소
   * @param emotionRepository 그림 활동 선택 감정 저장소
   * @param htpAssessmentRepository HTP 묶음의 세 세션 집계와 상태 전이 저장소
   * @param subjectRepository 주제(집·나무·사람)별 관찰 묶음 저장소 (S15P11B209-960)
   * @param referenceRepository 리포트 참고 자료 저장소 (S15P11B209-960)
   * @param behaviorSummaryService 저장된 Stroke 배치에서 그리기 행동 수치를 집계하는 경계 (S15P11B209-870)
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
      ReportDrawnItemRepository drawnItemRepository,
      ReportPublicInterpretationRepository interpretationRepository,
      ReportEvidenceItemRepository evidenceItemRepository,
      ReportParentGuideRepository parentGuideRepository,
      ReportCrisisAlertRepository crisisAlertRepository,
      ReportSubjectRepository subjectRepository,
      ReportReferenceRepository referenceRepository,
      InterpretationSafetyVerifier safetyVerifier,
      InterpretationCandidateAdapter candidateAdapter,
      ReportObservedFeatureRepository observedFeatureRepository,
      ReportKeyConversationRepository keyConversationRepository,
      ReportFollowUpGuideRepository followUpGuideRepository,
      ReportGuardianQuestionRepository guardianQuestionRepository,
      ConversationSessionRepository conversationSessionRepository,
      ConversationMessageRepository conversationMessageRepository,
      DrawingSessionEmotionRepository emotionRepository,
      HtpAssessmentRepository htpAssessmentRepository,
      StrokeBehaviorSummaryService behaviorSummaryService,
      ApplicationEventPublisher eventPublisher,
      Clock clock) {
    this.analysisRepository = analysisRepository;
    this.reportRepository = reportRepository;
    this.observationResultRepository = observationResultRepository;
    this.conversationSummaryRepository = conversationSummaryRepository;
    this.activitySummaryRepository = activitySummaryRepository;
    this.activityNoteRepository = activityNoteRepository;
    this.drawnItemRepository = drawnItemRepository;
    this.interpretationRepository = interpretationRepository;
    this.evidenceItemRepository = evidenceItemRepository;
    this.parentGuideRepository = parentGuideRepository;
    this.crisisAlertRepository = crisisAlertRepository;
    this.subjectRepository = subjectRepository;
    this.referenceRepository = referenceRepository;
    this.safetyVerifier = safetyVerifier;
    this.candidateAdapter = candidateAdapter;
    this.observedFeatureRepository = observedFeatureRepository;
    this.keyConversationRepository = keyConversationRepository;
    this.followUpGuideRepository = followUpGuideRepository;
    this.guardianQuestionRepository = guardianQuestionRepository;
    this.conversationSessionRepository = conversationSessionRepository;
    this.conversationMessageRepository = conversationMessageRepository;
    this.emotionRepository = emotionRepository;
    this.htpAssessmentRepository = htpAssessmentRepository;
    this.behaviorSummaryService = behaviorSummaryService;
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
    // ⚠️ 이 목록은 아래에서 걸러지는 subjectContexts 와 달리 **모든 세션**을 담는다. 주제별
    //    그리기 시간(S15P11B209-975)의 이름표라 하나라도 빠지면 비교 관찰이 거짓이 된다.
    List<ObservationGenerationContext.ActivitySessionRef> contextSessions =
        htpAssessmentRepository
            .findStepByDrawingSessionId(drawingSessionId)
            .map(
                step ->
                    step.getAssessment().getSteps().stream()
                        .sorted(Comparator.comparingInt(HtpAssessmentStep::getStepOrder))
                        .map(
                            htpStep ->
                                new ObservationGenerationContext.ActivitySessionRef(
                                    htpStep.getDrawingSession().getId(),
                                    htpStep.getDrawingSubject().name()))
                        .toList())
            .orElseGet(
                () ->
                    List.of(
                        new ObservationGenerationContext.ActivitySessionRef(
                            drawingSessionId, null)));
    List<Long> contextSessionIds =
        contextSessions.stream()
            .map(ObservationGenerationContext.ActivitySessionRef::drawingSessionId)
            .toList();

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
    for (ObservationGenerationContext.ActivitySessionRef contextSession : contextSessions) {
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
                  source.getAnswerType(),
                  source.getAnswerNeedsGuardianConfirmation());
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
      List<DrawingDetectedObject> detections =
          subjectObservation == null ? List.of() : subjectObservation.getAnalysis().getDetections();
      // 코드 목록은 탐지 전부를 담는다 — 좌표계와 무관하게 관찰 서술의 재료이기 때문이다.
      List<String> detectedObjectCodes =
          detections.stream().map(DrawingDetectedObject::getLabel).toList();
      // 코드만 뽑아 버리면 AI 가 근거를 가리킬 때 조합키를 조립할 수밖에 없다(계약 §4에서 금지).
      // 같은 재료를 행 식별자·정규화 기하와 함께 담아 참조 가능한 형태로 보낸다 (S15P11B209-906/837).
      //   PIXEL 행을 거르는 이유는 아래 isNormalized javadoc.
      List<ObservationGenerationContext.DetectedObjectRef> detectedObjects =
          detections.stream()
              .filter(ObservationReportPersistenceService::isNormalized)
              .map(
                  detection ->
                      new ObservationGenerationContext.DetectedObjectRef(
                          detection.getId(),
                          detection.getLabel(),
                          detection.getX(),
                          detection.getY(),
                          detection.getWidth(),
                          detection.getHeight(),
                          // areaRatio 는 저장된 값만 쓴다. width * height 로 채우지 않는다 —
                          //   추정값을 관찰 사실로 적으면 근거가 아닌 것이 근거 자리에 들어간다(AI 계약 명시).
                          detection.getAreaRatio(),
                          detection.getConfidence()))
              .toList();
      Long observationResultId = subjectObservation == null ? null : subjectObservation.getId();
      // 서술·코드·문답이 전부 비면 담지 않는다 — 빈 항목은 AI 프롬프트에 노이즈만 더한다.
      if (drawingDescription != null
          || !detectedObjectCodes.isEmpty()
          || !subjectQaPairs.isEmpty()) {
        subjectContexts.add(
            new ObservationGenerationContext.SubjectContext(
                contextSession.drawingSubject(),
                drawingDescription,
                detectedObjectCodes,
                subjectQaPairs,
                observationResultId,
                detectedObjects,
                contextSessionId));
      }
    }

    List<DrawingSessionEmotion> emotionSources =
        contextSessionIds.size() == 1
            ? emotionRepository.findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
                drawingSessionId)
            : emotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
                    contextSessionIds);
    List<ObservationGenerationContext.SelectedEmotionRef> selectedEmotionRefs =
        emotionSources.stream()
            .map(
                emotion ->
                    new ObservationGenerationContext.SelectedEmotionRef(
                        emotion.getId(), emotion.getEmotionCode().name()))
            .toList();
    List<String> selectedEmotions =
        selectedEmotionRefs.stream()
            .map(ObservationGenerationContext.SelectedEmotionRef::emotionCode)
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
            keyConversations,
            subjectContexts,
            selectedEmotionRefs,
            contextSessions));
  }

  /**
   * 이 탐지 행의 좌표를 AI 에 보낼 수 있는지 판정한다 (S15P11B209-837).
   *
   * <p><b>정규화 좌표계만 통과시킨다.</b> AI 는 캔버스 원본 크기를 모르므로 픽셀 좌표로는 용지 점유율을 계산할 수 없다(계약 합의 사항). 픽셀값을 0~1 비율인
   * 것처럼 넘기면 <b>"종이의 대부분을 차지한다"</b> 같은 없는 관찰이 만들어진다 — 좌표 하나가 관찰 문장이 되는 경로라 좌표계를 틀리면 그대로 아이에 대한 거짓
   * 서술이 된다.
   *
   * <p>그래서 픽셀 행은 <b>변환하지 않고 뺀다.</b> 변환하려면 캔버스 원본 크기가 필요한데 탐지 행에도 자산 메타에도 없다. 없는 값을 추정해 채우느니 그 그림의
   * 기하를 보내지 않는 편이 옳다 — 코드 목록({@code detectedObjectCodes})은 그대로 실리므로 관찰 서술 재료는 잃지 않는다.
   *
   * <p>좌표가 하나라도 비어 있으면 역시 뺀다. 부분 좌표로는 위치도 크기도 말할 수 없다.
   *
   * @param detection 탐지 행
   * @return 정규화 좌표 네 값이 모두 있으면 {@code true}
   */
  private static boolean isNormalized(DrawingDetectedObject detection) {
    return detection.getCoordinateSpace() == DrawingCoordinateSpace.NORMALIZED
        && detection.getX() != null
        && detection.getY() != null
        && detection.getWidth() != null
        && detection.getHeight() != null;
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
      analysis.succeedFinal(
          ColumnTextLimiter.fit(result.modelName(), MODEL_NAME_LIMIT, "analyses.model_name"),
          ColumnTextLimiter.fit(
              result.modelVersion(), MODEL_VERSION_LIMIT, "analyses.model_version"),
          result.confidence(),
          now);

      // AI 가 실어 보낸 검토 상태를 그대로 저장한다. 모르는 값·null 은 fromAiStatus 가 초안으로 떨어뜨리므로
      //   해석 실패는 "공개하지 않는다" 쪽으로만 기운다.
      AnalysisObservationResult observation =
          AnalysisObservationResult.of(
              analysis,
              1,
              draft.overallSummary(),
              draft.positiveSignals(),
              draft.attentionPoints(),
              draft.evidenceSummary(),
              draft.guardianGuidance(),
              draft.followUpQuestion(),
              draft.expertReviewRequired(),
              ObservationReviewStatus.fromAiStatus(draft.status()),
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

      StrokeBehaviorSummary behavior = aggregateBehavior(context);
      activitySummaryRepository.save(
          ReportActivitySummary.create(
              report,
              behavior == null ? null : behavior.drawingDurationMs(),
              behavior == null ? null : behavior.pauseCount(),
              behavior == null ? null : behavior.eraseCount(),
              behavior != null && behavior.pressureAvailable(),
              context.questionCount(),
              context.answeredCount(),
              context.skippedCount(),
              summary == null ? null : summary.summaryText()));

      boolean reviewed = observation.getReviewStatus().isReviewed();
      saveActivityNotes(report, safeList(result.activityNotes()));
      saveDrawnItems(report, result);
      saveObservedFeatures(report, draft.features(), reviewed);
      saveKeyConversations(report, context.keyConversations());
      saveFollowUpGuides(report, safeList(result.followUpGuides()));
      saveGuardianQuestions(report, safeList(result.guardianQuestions()));
      // 875 §3·§4·§7·§7-1·§5·§9. 저장 메서드는 902 가 만들었지만 호출되지 않은 채였다 — 그래서
      //   경향 해석·근거·보호자 가이드·위기 안내가 한 건도 저장된 적이 없다. 주제별 관찰은 카드가
      //   저장된 뒤에 참조를 걸어야 하므로 반드시 이 순서다.
      Map<Integer, ReportPublicInterpretation> savedCards =
          savePublicInterpretations(report, result);
      saveParentGuides(report, safeList(result.parentGuides()));
      saveCrisisAlert(report, result.crisisAlert());
      saveSubjects(report, context, result, savedCards);
      saveReferences(report, safeList(result.ragReferences()));

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

  /**
   * 이 리포트가 다루는 세션들의 그리기 행동 수치를 합친다 (S15P11B209-870).
   *
   * <p>이전에는 이 자리에 {@code null} 을 넣어, S15P11B209-772 가 집계해 AI 로 보내던 수치가 <b>리포트에는 한 자리도 남지 않았다.</b>
   * 보호자는 아이가 얼마나 그렸고 몇 번 멈췄는지 볼 수 없었다.
   *
   * <p>집계 실패로 리포트 생성을 죽이지 않는다. 읽는 곳이 MongoDB 라 JPA Transaction 과 별개로 실패할 수 있고, 그때 리포트 전체를 잃는 것은 균형에
   * 맞지 않는다 — 행동 수치는 리포트의 부가 정보다. 실패하면 경고만 남기고 수치를 {@code null} 로 둔다(S15P11B209-815 에서 리포트 생성이 전면
   * 실패한 것과 같은 실패 확산을 막는다).
   *
   * @param context 대상 세션 목록을 가진 생성 맥락
   * @return 합산된 행동 요약이며 집계할 배치가 없거나 집계에 실패하면 {@code null}
   */
  private StrokeBehaviorSummary aggregateBehavior(ObservationGenerationContext context) {
    List<Long> sessionIds = context.activitySessionIds();
    if (sessionIds == null || sessionIds.isEmpty()) {
      sessionIds = List.of(context.drawingSessionId());
    }
    try {
      return behaviorSummaryService.summarizeAll(sessionIds).orElse(null);
    } catch (RuntimeException exception) {
      log.warn(
          "그리기 행동 수치 집계에 실패해 리포트에 수치를 남기지 않습니다. reportId={}, sessionIds={}, exceptionType={}, message={}",
          context.reportId(),
          sessionIds,
          exception.getClass().getName(),
          exception.getMessage());
      return null;
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

  /**
   * AI가 명시적으로 보낸 관찰 서술 기반 항목만 저장한다.
   *
   * <p>필드 자체가 없는 이전 AI 응답은 표식을 남기지 않아 과거 리포트의 0.50 YOLO 폴백을 유지한다. 반대로 빈 배열은 정상 결과이므로 표식을 남겨 폴백하지
   * 않는다. 계약상 20자를 넘거나 이름이 비었거나 항목이 null인 응답 조각은 리포트 전체를 실패시키지 않고 버린다.
   */
  private void saveDrawnItems(Report report, ObservationGenerationResult result) {
    if (!result.hasDrawnItems()) {
      return;
    }
    List<ReportDrawnItem> entities = new ArrayList<>();
    for (DrawnItemDraft item : result.drawnItemsOrEmpty()) {
      if (item == null || !isDisplayableDrawnItemName(item.name())) {
        continue;
      }
      entities.add(
          ReportDrawnItem.create(report, entities.size(), item.drawingSubject(), item.name()));
    }
    drawnItemRepository.saveAll(entities);
    report.markDrawnItemsStored();
  }

  /**
   * 주제(집·나무·사람)별 관찰 묶음을 저장한다 (875 §5 / S15P11B209-960).
   *
   * <p><b>소유가 갈린 자리다.</b> 관찰 서술과 경향 해석 참조는 AI 가 보내고({@code subjectReports}), 완성 그림과 문답은 BE 가 채운다 —
   * AI 는 그림 URL 을 만들 수 없고, 아이 발화를 LLM 에 되돌려 받으면 원문이 바뀌기 때문이다(S15P11B209-941). 그래서 두 출처를 주제 키로 합친다.
   *
   * <p><b>주제 목록의 기준은 BE 다.</b> 어떤 주제를 실제로 그렸는지는 서버가 알고, AI 는 서술을 붙일 뿐이다. AI 만 아는 주제가 오면 함께 담되(서술을
   * 버리지 않는다) 서버가 아는 주제를 AI 응답 때문에 빠뜨리지는 않는다.
   *
   * <p><b>순서는 계약이다</b> — 875 §5 가 {@code HOUSE → TREE → PERSON}을 보장한다.
   *
   * @param report 묶음이 속한 리포트
   * @param context 주제별 세션·문답을 담은 생성 맥락
   * @param result AI 응답
   * @param savedCards AI 응답 배열 인덱스를 Key 로 하는 저장된 경향 해석 카드
   */
  private void saveSubjects(
      Report report,
      ObservationGenerationContext context,
      ObservationGenerationResult result,
      Map<Integer, ReportPublicInterpretation> savedCards) {
    Map<String, SubjectMergeEntry> merged = new LinkedHashMap<>();
    for (ObservationGenerationContext.SubjectContext subject :
        safeList(context.subjectContexts())) {
      if (subject == null) {
        continue;
      }
      merged
          .computeIfAbsent(subjectKey(subject.drawingSubject()), key -> new SubjectMergeEntry())
          .bindContext(subject);
    }
    for (ObservationGenerationResult.SubjectReportDraft draft : safeList(result.subjectReports())) {
      if (draft == null) {
        continue;
      }
      merged
          .computeIfAbsent(subjectKey(draft.subjectType()), key -> new SubjectMergeEntry())
          .bindDraft(draft);
    }
    if (merged.isEmpty()) {
      return;
    }

    List<Map.Entry<String, SubjectMergeEntry>> ordered = new ArrayList<>(merged.entrySet());
    ordered.sort(Comparator.comparingInt(entry -> subjectRank(entry.getKey())));

    List<ReportSubject> entities = new ArrayList<>();
    for (Map.Entry<String, SubjectMergeEntry> entry : ordered) {
      SubjectMergeEntry value = entry.getValue();
      // 그림도 서술도 문답도 없는 주제는 담지 않는다 — 화면에 빈 카드만 남는다(875 §10).
      if (value.isEmpty()) {
        continue;
      }
      ReportSubject subject =
          ReportSubject.create(
              report, entities.size(), emptyToNull(entry.getKey()), value.drawingSessionId);
      for (String observation : value.visionObservations) {
        if (observation != null && !observation.isBlank()) {
          subject.addObservation(observation);
        }
      }
      int representativeCount = 0;
      for (ObservationGenerationContext.KeyConversationLine line : value.qaPairs) {
        if (line == null || line.questionText() == null || line.questionText().isBlank()) {
          continue;
        }
        boolean answered = line.answerText() != null && !line.answerText().isBlank();
        // 대표 문답은 화면이 먼저 펼치는 최대 3개다(875 §6). 답하지 않은 문답을 대표로 올리지 않는다.
        boolean representative = answered && representativeCount < MAX_REPRESENTATIVE_QA_PAIRS;
        if (representative) {
          representativeCount++;
        }
        subject.addQaPair(
            line.questionText(),
            line.answerText(),
            answered ? ReportSubjectQaPair.STATE_ANSWERED : ReportSubjectQaPair.STATE_SKIPPED,
            line.answerType(),
            line.sttNeedsConfirmation(),
            representative);
      }
      // 참조는 공개된 카드에만 건다. 제외·강등 카드는 보호자 응답 배열에 없으므로 참조가 가리킬 자리가 없다.
      for (Integer ref : value.interpretationRefs) {
        ReportPublicInterpretation card = ref == null ? null : savedCards.get(ref);
        if (card != null
            && card.getDisclosureState() == ReportInterpretationDisclosureState.PUBLISHED) {
          subject.referenceInterpretation(card);
        }
      }
      entities.add(subject);
    }
    subjectRepository.saveAll(entities);
  }

  /**
   * 리포트가 참조한 전문 자료 출처를 저장한다 (875 §9, S15P11B209-614).
   *
   * <p>출처 표시는 라이선스 의무(KOGL-1)라 받은 것을 버리지 않는다. AI 는 링크를 보내지 않으므로 {@code url}은 항상 {@code null}이다.
   *
   * @param report 자료가 속한 리포트
   * @param drafts AI 가 보낸 출처 목록
   */
  private void saveReferences(
      Report report, List<ObservationGenerationResult.RagReferenceDraft> drafts) {
    List<ReportReference> entities = new ArrayList<>();
    Set<String> seenTitles = new LinkedHashSet<>();
    for (ObservationGenerationResult.RagReferenceDraft draft : drafts) {
      if (draft == null || draft.title() == null || draft.title().isBlank()) {
        continue;
      }
      // 같은 자료의 여러 청크가 하나의 출처로 오므로 제목이 겹친다. 목록에 같은 줄을 두 번 싣지 않는다.
      if (!seenTitles.add(draft.title())) {
        continue;
      }
      entities.add(
          ReportReference.create(
              report,
              entities.size(),
              ColumnTextLimiter.fit(
                  draft.sourceId(),
                  ReportReference.SOURCE_ID_MAX_LENGTH,
                  "report_references.source_id"),
              ColumnTextLimiter.fit(
                  draft.title(), ReportReference.TITLE_MAX_LENGTH, "report_references.title"),
              null));
    }
    referenceRepository.saveAll(entities);
  }

  /** 주제별 관찰의 두 출처(BE 맥락·AI 응답)를 주제 키로 합치는 중간 값이다. */
  private static final class SubjectMergeEntry {
    private Long drawingSessionId;
    private List<ObservationGenerationContext.KeyConversationLine> qaPairs = List.of();
    private List<String> visionObservations = List.of();
    private List<Integer> interpretationRefs = List.of();

    private void bindContext(ObservationGenerationContext.SubjectContext subject) {
      this.drawingSessionId = subject.drawingSessionId();
      this.qaPairs = safeList(subject.qaPairs());
    }

    private void bindDraft(ObservationGenerationResult.SubjectReportDraft draft) {
      this.visionObservations = safeList(draft.visionObservations());
      this.interpretationRefs = safeList(draft.interpretationRefs());
    }

    private boolean isEmpty() {
      return drawingSessionId == null && qaPairs.isEmpty() && visionObservations.isEmpty();
    }
  }

  /** 주제 키를 정규화한다. 주제가 없는 활동(그림일기)은 빈 문자열 하나로 모인다. */
  private static String subjectKey(String subjectType) {
    if (subjectType == null || subjectType.isBlank()) {
      return "";
    }
    String normalized = subjectType.trim().toUpperCase(Locale.ROOT);
    return SUBJECT_ORDER.contains(normalized) ? normalized : "";
  }

  /** 875 §5 가 보장하는 노출 순서다. 주제가 없는 활동은 뒤로 보낸다. */
  private static int subjectRank(String subjectKey) {
    int rank = SUBJECT_ORDER.indexOf(subjectKey);
    return rank < 0 ? SUBJECT_ORDER.size() : rank;
  }

  private static String emptyToNull(String value) {
    return value == null || value.isEmpty() ? null : value;
  }

  private static boolean isDisplayableDrawnItemName(String name) {
    return name != null
        && !name.isBlank()
        && name.codePointCount(0, name.length()) <= ReportDrawnItem.DISPLAY_NAME_MAX_CODE_POINTS;
  }

  /**
   * 경향 해석과 근거를 2단 검증 결과에 따라 저장한다 (S15P11B209-902).
   *
   * <p>기존 관찰 특징({@code report_observed_features}) 경로를 쓰지 않는다 — 그쪽은 {@code resolveVisibility()}가 전문가
   * 검토 전 항목을 전부 EXPERT_ONLY 로 강등하고 그 판단에 쓰는 검토 상태는 전이 경로가 없어 항상 미검토다. 실으면 구현이 끝나도 보호자 화면이 빈다(계약
   * §4-2 결정 1).
   *
   * <p>AI 도 자체 게이트를 통과시킨 카드만 보내지만 여기서 다시 검증한다 — 이중 방어이며, 서버가 발급하지 않은 참조나 근거 부족을 서버 쪽에서 확정한다.
   *
   * @param report 카드가 속한 리포트
   * @param result AI 응답
   * @return AI 응답 배열 인덱스를 Key 로 하는 저장된 카드 Map 이다. 주제별 관찰의 {@code interpretationRefs}가 이 인덱스로 오므로
   *     참조를 카드 행으로 바꾸려면 이 Map 이 필요하다 (S15P11B209-960)
   */
  private Map<Integer, ReportPublicInterpretation> savePublicInterpretations(
      Report report, ObservationGenerationResult result) {
    List<ObservationGenerationResult.PublicInterpretationDraft> cardDrafts =
        safeList(result.publicInterpretations());
    if (cardDrafts.isEmpty()) {
      return Map.of();
    }
    List<ObservationGenerationResult.EvidenceItemDraft> evidenceDrafts =
        safeList(result.evidenceItems());

    List<InterpretationCandidate> candidates = candidateAdapter.toCandidates(cardDrafts);
    InterpretationSafetyOutcome outcome =
        safetyVerifier.verify(candidates, candidateAdapter.toEvidenceCandidates(evidenceDrafts));

    // 근거는 공개 여부와 무관하게 저장한다 — 제외·강등 카드도 왜 그렇게 됐는지 되짚어야 한다.
    Map<Long, ReportEvidenceItem> savedEvidence = saveEvidenceItems(report, evidenceDrafts);

    Map<Integer, ReportPublicInterpretation> cards = new LinkedHashMap<>();
    int order = 0;
    for (InterpretationSafetyOutcome.PublishedInterpretation published : outcome.published()) {
      cards.put(published.sourceIndex(), newInterpretation(report, order++, published.candidate()));
    }
    for (InterpretationSafetyOutcome.DemotedInterpretation demoted : outcome.demoted()) {
      cards.put(demoted.sourceIndex(), newInterpretation(report, order++, demoted.candidate()));
    }
    for (InterpretationSafetyOutcome.ExcludedInterpretation excluded : outcome.excluded()) {
      cards.put(excluded.sourceIndex(), newInterpretation(report, order++, excluded.candidate()));
    }

    // 근거 연결은 판정과 무관하게 붙인다. 참조가 남아 있어야 사유를 검증할 수 있다.
    for (Map.Entry<Integer, ReportPublicInterpretation> entry : cards.entrySet()) {
      InterpretationCandidate candidate = candidateAt(candidates, entry.getKey());
      if (candidate == null) {
        continue;
      }
      for (Long evidenceRef : candidate.evidenceRefs()) {
        ReportEvidenceItem evidenceItem = savedEvidence.get(evidenceRef);
        if (evidenceItem != null) {
          entry.getValue().referenceEvidence(evidenceItem);
        }
      }
    }

    for (InterpretationSafetyOutcome.PublishedInterpretation published : outcome.published()) {
      ReportPublicInterpretation card = cards.get(published.sourceIndex());
      if (card != null && !card.getEvidences().isEmpty()) {
        card.publish();
      }
    }
    for (InterpretationSafetyOutcome.DemotedInterpretation demoted : outcome.demoted()) {
      ReportPublicInterpretation card = cards.get(demoted.sourceIndex());
      if (card != null) {
        card.restrictToExpert(demoted.reason().name());
      }
    }
    for (InterpretationSafetyOutcome.ExcludedInterpretation excluded : outcome.excluded()) {
      ReportPublicInterpretation card = cards.get(excluded.sourceIndex());
      if (card != null) {
        card.withhold(firstReason(excluded));
      }
    }

    interpretationRepository.saveAll(cards.values());
    return cards;
  }

  /**
   * 근거 풀을 저장하고 AI 로컬 번호로 찾을 수 있는 Map 을 돌려준다.
   *
   * <p>AI 의 {@code evidenceId}는 응답 안에서만 유일한 로컬 번호이므로 그대로 {@code evidence_number}로 보존한다. 카드의 {@code
   * evidenceRefs}가 이 번호를 가리키기 때문이다.
   *
   * @param report 근거가 속한 리포트
   * @param drafts AI 가 보낸 근거 목록
   * @return AI 로컬 번호를 Key 로 하는 저장된 근거 Map
   */
  private Map<Long, ReportEvidenceItem> saveEvidenceItems(
      Report report, List<ObservationGenerationResult.EvidenceItemDraft> drafts) {
    Map<Long, ReportEvidenceItem> saved = new LinkedHashMap<>();
    for (ObservationGenerationResult.EvidenceItemDraft draft : drafts) {
      if (draft == null || draft.evidenceId() == null || draft.text() == null) {
        continue;
      }
      ReportEvidenceSourceType sourceType =
          parseEnum(ReportEvidenceSourceType.class, draft.sourceType());
      if (sourceType == null) {
        continue;
      }
      int evidenceNumber = draft.evidenceId().intValue();
      if (evidenceNumber <= 0 || saved.containsKey(draft.evidenceId())) {
        continue;
      }
      String text =
          ColumnTextLimiter.fit(draft.text(), EVIDENCE_TEXT_LIMIT, "report_evidence_items.text");
      try {
        ReportEvidenceItem item =
            sourceType.isDerived()
                ? ReportEvidenceItem.derived(
                    report,
                    evidenceNumber,
                    sourceType,
                    text,
                    toDomainRefs(draft.derivedFrom()),
                    draft.sttNeedsConfirmation())
                : ReportEvidenceItem.original(
                    report,
                    evidenceNumber,
                    sourceType,
                    text,
                    domainKind(draft.sourceRef()),
                    domainRefId(draft.sourceRef()),
                    draft.sttNeedsConfirmation());
        saved.put(draft.evidenceId(), item);
      } catch (IllegalArgumentException | NullPointerException exception) {
        // 배타 규칙·식별자 형식을 지키지 않은 근거는 버린다. 근거 한 건 때문에 리포트를 죽이지 않는다.
        log.info("경향 해석 근거를 저장하지 않았다. evidenceId={}", draft.evidenceId());
      }
    }
    evidenceItemRepository.saveAll(saved.values());
    return saved;
  }

  /**
   * 유형별 보호자 가이드를 저장한다. AI 는 유형마다 문장 목록을 보내므로 행으로 펼친다.
   *
   * @param report 가이드가 속한 리포트
   * @param drafts AI 가 보낸 가이드 목록
   */
  private void saveParentGuides(
      Report report, List<ObservationGenerationResult.ParentGuideDraft> drafts) {
    List<ReportParentGuide> entities = new ArrayList<>();
    for (ObservationGenerationResult.ParentGuideDraft draft : drafts) {
      if (draft == null) {
        continue;
      }
      ReportParentGuideType guideType = parseEnum(ReportParentGuideType.class, draft.guideType());
      if (guideType == null) {
        continue;
      }
      int order = 0;
      for (String item : draft.items()) {
        if (item == null || item.isBlank()) {
          continue;
        }
        entities.add(ReportParentGuide.create(report, guideType, order++, item));
      }
    }
    parentGuideRepository.saveAll(entities);
  }

  /**
   * 위기 대응 안내를 저장한다.
   *
   * <p>{@code ABUSE_DISCLOSURE}는 저장하지 않는다 — 가해자가 보호자일 수 있어 자동 통지가 아이를 위험하게 한다. AI 가 이미 만들지
   * 않지만(S15P11B209-890) 여기서도 막아 매핑이 되돌아가도 보호자 노출 경로로 새지 않게 한다.
   *
   * @param report 안내가 속한 리포트
   * @param draft AI 가 보낸 위기 안내이며 없으면 {@code null}
   */
  private void saveCrisisAlert(Report report, ObservationGenerationResult.CrisisAlertDraft draft) {
    if (draft == null || !ReportCrisisAlert.isStorableReason(draft.reasonCode())) {
      return;
    }
    try {
      ReportCrisisAlert alert =
          ReportCrisisAlert.create(
              report,
              draft.reasonCode(),
              draft.severity(),
              ColumnTextLimiter.fit(
                  draft.title(), CRISIS_TITLE_LIMIT, "report_crisis_alerts.title"),
              draft.message());
      for (String step : draft.actionSteps()) {
        if (step != null && !step.isBlank()) {
          alert.addStep(step);
        }
      }
      for (ObservationGenerationResult.CrisisResourceDraft resource : draft.resources()) {
        if (resource == null) {
          continue;
        }
        alert.addResource(
            ColumnTextLimiter.fit(
                resource.name(),
                CRISIS_RESOURCE_NAME_LIMIT,
                "report_crisis_alert_resources.resource_name"),
            ColumnTextLimiter.fit(
                resource.contact(), CRISIS_CONTACT_LIMIT, "report_crisis_alert_resources.contact"),
            ColumnTextLimiter.fit(
                resource.note(), CRISIS_NOTE_LIMIT, "report_crisis_alert_resources.note"));
      }
      crisisAlertRepository.save(alert);
    } catch (IllegalArgumentException | NullPointerException exception) {
      log.info("위기 대응 안내를 저장하지 않았다. reasonCode={}", draft.reasonCode());
    }
  }

  private ReportPublicInterpretation newInterpretation(
      Report report, int displayOrder, InterpretationCandidate candidate) {
    return ReportPublicInterpretation.create(
        report,
        displayOrder,
        ReportInterpretationCategory.valueOf(candidate.category().name()),
        ColumnTextLimiter.fit(
            candidate.title(), INTERPRETATION_TITLE_LIMIT, "report_public_interpretations.title"),
        candidate.tendencyText(),
        candidate.scopeText(),
        candidate.homeObservationGuide());
  }

  private static InterpretationCandidate candidateAt(
      List<InterpretationCandidate> candidates, int index) {
    return index >= 0 && index < candidates.size() ? candidates.get(index) : null;
  }

  private static String firstReason(InterpretationSafetyOutcome.ExcludedInterpretation excluded) {
    return excluded.reasons().stream()
        .findFirst()
        .map(Enum::name)
        .orElse(ReportPublicInterpretation.PENDING_VERIFICATION);
  }

  private static List<ReportEvidenceSourceRef> toDomainRefs(
      List<ObservationGenerationResult.EvidenceSourceRefDraft> refs) {
    List<ReportEvidenceSourceRef> domainRefs = new ArrayList<>();
    for (ObservationGenerationResult.EvidenceSourceRefDraft ref : refs) {
      ReportEvidenceSourceKind kind = domainKind(ref);
      if (kind != null && ref.id() != null && !ref.id().isBlank()) {
        domainRefs.add(new ReportEvidenceSourceRef(kind, ref.id()));
      }
    }
    return domainRefs;
  }

  private static ReportEvidenceSourceKind domainKind(
      ObservationGenerationResult.EvidenceSourceRefDraft ref) {
    return ref == null ? null : parseEnum(ReportEvidenceSourceKind.class, ref.kind());
  }

  private static String domainRefId(ObservationGenerationResult.EvidenceSourceRefDraft ref) {
    return ref == null ? null : ref.id();
  }

  private static <E extends Enum<E>> E parseEnum(Class<E> type, String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    try {
      return Enum.valueOf(type, value.trim().toUpperCase(java.util.Locale.ROOT));
    } catch (IllegalArgumentException exception) {
      return null;
    }
  }

  /**
   * 관찰 특징을 노출 범위와 함께 저장한다 (S15P11B209-931).
   *
   * <p>위 {@code savePublicInterpretations} 와 저장·노출 경로가 다르다. 경향 해석은 계약 §4-2 대로 {@code
   * resolveVisibility()} 를 타지 않지만, 관찰 특징은 이 경로를 그대로 쓰되 판단 재료인 검토 상태에 {@code AI_REVIEWED} 가 생겨 비로소
   * 통과 가능해졌다 — 그전에는 전이 경로가 없어 항상 미검토였고, 그래서 97건 전부가 EXPERT_ONLY 였다.
   *
   * @param report 대상 리포트
   * @param features AI 가 보낸 관찰 특징 초안 목록
   * @param reviewed 이 리포트의 관찰 결과가 검토를 통과했는지 여부
   */
  private void saveObservedFeatures(
      Report report, List<ObservedFeatureDraft> features, boolean reviewed) {
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
              resolveVisibility(feature.visibilityScope(), reviewed),
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

  /**
   * 관찰 특징 하나의 노출 범위를 확정한다.
   *
   * <p><b>두 조건을 모두 만족해야 보호자에게 열린다.</b> ① 리포트의 관찰 결과가 검토를 통과했고({@link
   * ObservationReviewStatus#isReviewed()}), ② AI 가 그 특징을 {@code REVIEWED_GUARDIAN} 으로 표시했다. 리포트 단위
   * 판정과 항목 단위 판정이 따로 있는 이유는, 검토를 통과한 리포트 안에서도 개별 항목은 보호자에게 바로 열지 않는 편이 나은 것이 섞이기 때문이다.
   *
   * <p>{@code AI_REVIEWED} 가 생기기 전에는 ①이 <b>구조적으로 항상 거짓</b>이어서 모든 특징이 {@code EXPERT_ONLY} 로 떨어졌다.
   * 그리고 <b>기존 테스트는 전부 통과했다</b> — 전부 "노출되지 않는지"만 확인했기 때문이다. 이 함수를 고칠 때는 <b>열리는 경로를 검증하는 테스트</b>가 반드시
   * 함께 있어야 한다.
   *
   * <p>{@code EXPERT_ONLY} 는 이제 "사람 전문가 대기열"이 아니라 <b>보호자에게 바로 열지 않는다</b>는 뜻이다 — 사람 상담 권유·위기 경로에서만
   * 쓴다.
   *
   * @param value AI 가 보낸 노출 범위 문자열
   * @param reviewed 리포트의 관찰 결과가 검토를 통과했는지 여부
   * @return 확정된 노출 범위이며 판정할 수 없으면 {@link ReportFeatureVisibility#EXPERT_ONLY}
   */
  private static ReportFeatureVisibility resolveVisibility(String value, boolean reviewed) {
    if (reviewed && "REVIEWED_GUARDIAN".equals(value)) {
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
