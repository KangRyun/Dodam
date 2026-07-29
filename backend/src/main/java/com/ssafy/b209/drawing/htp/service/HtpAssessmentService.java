package com.ssafy.b209.drawing.htp.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.request.SaveDrawingReflectionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingReflectionResponse;
import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.htp.dto.HtpAssessmentResponse;
import com.ssafy.b209.drawing.htp.dto.HtpAssessmentStepResponse;
import com.ssafy.b209.drawing.htp.dto.HtpCompletionResponse;
import com.ssafy.b209.drawing.htp.dto.StartHtpAssessmentRequest;
import com.ssafy.b209.drawing.htp.exception.HtpErrorCode;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import com.ssafy.b209.drawing.service.DrawingReflectionService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.repository.ReportRepository;
import com.ssafy.b209.report.service.ReportGenerationRequestedEvent;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

/**
 * HTP 활동 묶음과 HOUSE, TREE, PERSON 그림 세션의 생성·조회·단계 전이를 조정한다.
 *
 * <p>그림 저장·분석·대화는 기존 그림 세션 API를 그대로 사용한다. 이 서비스는 현재 단계의 대화가 종료됐을 때만 해당 세션을 개별 리포트 없이 완료하고 다음 주제 세션을
 * 생성한다.
 */
@Service
@Transactional(isolation = Isolation.READ_COMMITTED)
public class HtpAssessmentService {

  private static final String HTP_TYPE_CODE = "HTP";
  private static final Duration HTP_VALIDITY = Duration.ofHours(24);
  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;
  private static final Pattern CONTROL_CHARACTER = Pattern.compile("\\p{Cntrl}");

  private final ChildRepository childRepository;
  private final DrawingTypeRepository drawingTypeRepository;
  private final DrawingSessionRepository drawingSessionRepository;
  private final HtpAssessmentRepository htpAssessmentRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final DrawingAssetRepository drawingAssetRepository;
  private final DrawingAnalysisRepository drawingAnalysisRepository;
  private final ReportRepository reportRepository;
  private final ApplicationEventPublisher eventPublisher;
  private final DrawingReflectionService drawingReflectionService;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final Clock clock;

  /**
   * HTP 상태 전이에 필요한 저장소와 인증 도구, 서버 시계를 주입받는다.
   *
   * @param childRepository 아동 잠금 조회 저장소
   * @param drawingTypeRepository HTP 유형 조회 저장소
   * @param drawingSessionRepository 단계별 그림 세션 저장소
   * @param htpAssessmentRepository HTP 묶음 저장소
   * @param conversationSessionRepository 단계별 대화 완료 조회 저장소
   * @param currentUserResolver 현재 보호자 식별자 Resolver
   * @param accessValidator 보호자와 아동의 연결 관계 Validator
   * @param clock 만료와 상태 전이 시각을 결정하는 서버 시계
   */
  public HtpAssessmentService(
      ChildRepository childRepository,
      DrawingTypeRepository drawingTypeRepository,
      DrawingSessionRepository drawingSessionRepository,
      HtpAssessmentRepository htpAssessmentRepository,
      ConversationSessionRepository conversationSessionRepository,
      DrawingAssetRepository drawingAssetRepository,
      DrawingAnalysisRepository drawingAnalysisRepository,
      ReportRepository reportRepository,
      ApplicationEventPublisher eventPublisher,
      DrawingReflectionService drawingReflectionService,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      Clock clock) {
    this.childRepository = childRepository;
    this.drawingTypeRepository = drawingTypeRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.htpAssessmentRepository = htpAssessmentRepository;
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingAssetRepository = drawingAssetRepository;
    this.drawingAnalysisRepository = drawingAnalysisRepository;
    this.reportRepository = reportRepository;
    this.eventPublisher = eventPublisher;
    this.drawingReflectionService = drawingReflectionService;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.clock = clock;
  }

  /**
   * HTP 묶음과 첫 HOUSE 그림 세션을 생성한다.
   *
   * @param idempotencyKey 시작 요청을 식별하는 {@code Idempotency-Key}
   * @param request 아동과 입력 방식
   * @return 생성했거나 멱등하게 다시 조회한 HTP 활동
   */
  public HtpAssessmentResponse start(String idempotencyKey, StartHtpAssessmentRequest request) {
    validateIdempotencyKey(idempotencyKey);
    Long guardianId = currentUserResolver.requireUserId();
    accessValidator.requireChildAccess(guardianId, request.childId());

    HtpAssessment existing =
        htpAssessmentRepository.findByIdempotencyKey(idempotencyKey).orElse(null);
    if (existing != null) {
      return existingStart(existing, request);
    }

    Child child =
        childRepository
            .findNotDeletedByIdForUpdate(request.childId())
            .filter(Child::isAvailable)
            .orElseThrow(() -> new BusinessException(HtpErrorCode.HTP_ASSESSMENT_NOT_FOUND));
    existing = htpAssessmentRepository.findByIdempotencyKeyForUpdate(idempotencyKey).orElse(null);
    if (existing != null) {
      return existingStart(existing, request);
    }
    DrawingType htpType =
        drawingTypeRepository
            .findByCode(HTP_TYPE_CODE)
            .filter(type -> type.isAvailableForAge(child.ageOn(LocalDate.now(clock))))
            .orElseThrow(() -> new BusinessException(HtpErrorCode.HTP_TYPE_NOT_AVAILABLE));
    LocalDateTime startedAt = now();
    HtpAssessment activeAssessment =
        htpAssessmentRepository.findActiveByChildIdForUpdate(child.getId()).orElse(null);
    if (activeAssessment != null) {
      if (request.replaceActive()
          && activeAssessment.getStatus() == HtpAssessmentStatus.IN_PROGRESS) {
        abandonActiveAssessment(activeAssessment, startedAt);
        htpAssessmentRepository.flush();
      } else if (activeAssessment.getStatus() == HtpAssessmentStatus.ANALYZING
          || startedAt.isBefore(activeAssessment.getExpiresAt())) {
        throw new BusinessException(HtpErrorCode.ACTIVE_ACTIVITY_EXISTS);
      } else {
        expire(activeAssessment, startedAt);
        htpAssessmentRepository.flush();
      }
    }
    DrawingSession activeSession =
        drawingSessionRepository.findActiveByChildId(child.getId()).orElse(null);
    if (activeSession != null) {
      if (!request.replaceActive()) {
        throw new BusinessException(HtpErrorCode.ACTIVE_ACTIVITY_EXISTS);
      }
      activeSession.abandon(startedAt);
    }

    DrawingSession houseSession =
        drawingSessionRepository.save(
            DrawingSession.start(child, htpType, request.inputMethod(), startedAt, idempotencyKey));
    HtpAssessment assessment =
        HtpAssessment.start(
            child, htpType, houseSession, startedAt, startedAt.plus(HTP_VALIDITY), idempotencyKey);
    return toResponse(htpAssessmentRepository.saveAndFlush(assessment));
  }

  private void abandonActiveAssessment(HtpAssessment activeAssessment, LocalDateTime abandonedAt) {
    DrawingSession currentSession = activeAssessment.getCurrentStep().getDrawingSession();
    if (currentSession.getSessionStatus() == DrawingSessionStatus.IN_PROGRESS) {
      currentSession.abandon(abandonedAt);
    }
    activeAssessment.abandon(abandonedAt);
  }

  /**
   * 현재 그림의 대화 완료를 확인하고 다음 HTP 주제 세션을 생성한다.
   *
   * <p>PERSON 단계에서는 현재 세션만 완료하고 네 번째 세션을 만들지 않는다.
   *
   * @param assessmentId HTP 활동 식별자
   * @param idempotencyKey 단계 변경 요청의 {@code Idempotency-Key}
   * @param nextInputMethod 다음 TREE 또는 PERSON 단계에서 사용할 그림 입력 방식
   * @return 다음 단계 또는 세 그림 완료 상태
   */
  public HtpAssessmentResponse nextStep(
      Long assessmentId, String idempotencyKey, DrawingInputMethod nextInputMethod) {
    validateIdempotencyKey(idempotencyKey);
    if (nextInputMethod == null) {
      throw new BusinessException(HtpErrorCode.HTP_TRANSITION_NOT_ALLOWED);
    }
    HtpAssessment assessment = findAuthorizedForUpdate(assessmentId);
    Optional<HtpAssessmentStep> processedStep =
        assessment.getSteps().stream()
            .filter(step -> step.hasProcessed(idempotencyKey))
            .findFirst();
    if (processedStep.isPresent()) {
      HtpAssessmentStep replayed = processedStep.get();
      if (replayed.getDrawingSubject() != HtpDrawingSubject.PERSON
          && replayed.getDrawingSession().getInputMethod() != nextInputMethod) {
        throw new BusinessException(HtpErrorCode.IDEMPOTENCY_KEY_CONFLICT);
      }
      return toResponse(assessment);
    }
    if (assessment.getStatus() != HtpAssessmentStatus.IN_PROGRESS
        || now().isAfter(assessment.getExpiresAt())) {
      throw new BusinessException(HtpErrorCode.HTP_TRANSITION_NOT_ALLOWED);
    }

    HtpAssessmentStep currentStep = assessment.getCurrentStep();
    DrawingSession currentSession = currentStep.getDrawingSession();
    conversationSessionRepository
        .findByDrawingSessionId(currentSession.getId())
        .filter(ConversationSession::isCompleted)
        .orElseThrow(() -> new BusinessException(HtpErrorCode.CURRENT_STEP_NOT_COMPLETED));
    try {
      currentStep.completeDrawingSession(idempotencyKey, now());
    } catch (IllegalStateException exception) {
      throw new BusinessException(HtpErrorCode.CURRENT_STEP_NOT_COMPLETED, exception);
    }

    if (currentStep.getDrawingSubject() == HtpDrawingSubject.PERSON) {
      return toResponse(assessment);
    }

    DrawingSession nextSession =
        drawingSessionRepository.save(
            DrawingSession.start(
                assessment.getChild(),
                assessment.getDrawingType(),
                nextInputMethod,
                now(),
                idempotencyKey));
    try {
      assessment.advance(nextSession, now());
    } catch (IllegalStateException exception) {
      throw new BusinessException(HtpErrorCode.HTP_TRANSITION_NOT_ALLOWED, exception);
    }
    return toResponse(assessment);
  }

  /**
   * HTP 활동과 현재 미완료 그림 세션을 포기 처리한다.
   *
   * @param assessmentId HTP 활동 식별자
   * @param idempotencyKey 포기 요청의 {@code Idempotency-Key}
   * @return 포기 상태로 저장된 HTP 활동
   */
  public HtpAssessmentResponse abandon(Long assessmentId, String idempotencyKey) {
    validateIdempotencyKey(idempotencyKey);
    HtpAssessment assessment = findAuthorizedForUpdate(assessmentId);
    if (assessment.getStatus() == HtpAssessmentStatus.ABANDONED) {
      return toResponse(assessment);
    }
    DrawingSession currentSession = assessment.getCurrentStep().getDrawingSession();
    if (currentSession.getSessionStatus() == DrawingSessionStatus.IN_PROGRESS) {
      currentSession.softDelete(now());
    }
    try {
      assessment.abandon(now());
    } catch (IllegalStateException exception) {
      throw new BusinessException(HtpErrorCode.HTP_TRANSITION_NOT_ALLOWED, exception);
    }
    return toResponse(assessment);
  }

  /**
   * HOUSE, TREE, PERSON 결과를 검증하고 HTP 묶음의 단일 리포트 생성을 접수한다.
   *
   * <p>주제별 그림 세션에는 리포트를 생성하지 않는다. PERSON 세션의 FINAL 파일은 기존 리포트 파이프라인을 실행하기 위한 대표 파일로만 사용하고, 리포트 입력의
   * 대화·감정 집계는 HTP 묶음의 세 세션을 기준으로 구성한다.
   *
   * @param assessmentId 완료할 HTP 활동 식별자
   * @param idempotencyKey 완료 요청을 식별하는 {@code Idempotency-Key}
   * @return 비동기 종합 리포트 작업의 접수 상태
   * @throws BusinessException 세 단계 결과가 준비되지 않았거나 다른 완료 요청과 충돌한 경우
   */
  public HtpCompletionResponse complete(Long assessmentId, String idempotencyKey) {
    validateIdempotencyKey(idempotencyKey);
    HtpAssessment assessment = findAuthorizedForUpdate(assessmentId);
    if (idempotencyKey.equals(assessment.getCompletionIdempotencyKey())) {
      return completionResponse(assessment);
    }
    if (assessment.getStatus() != HtpAssessmentStatus.IN_PROGRESS
        && assessment.getStatus() != HtpAssessmentStatus.FAILED) {
      throw new BusinessException(HtpErrorCode.HTP_COMPLETION_CONFLICT);
    }

    List<HtpAssessmentStep> steps = assessment.getSteps();
    if (steps.size() != 3
        || steps.get(0).getDrawingSubject() != HtpDrawingSubject.HOUSE
        || steps.get(1).getDrawingSubject() != HtpDrawingSubject.TREE
        || steps.get(2).getDrawingSubject() != HtpDrawingSubject.PERSON
        || steps.stream()
            .anyMatch(
                step ->
                    step.getDrawingSession().getSessionStatus()
                        != DrawingSessionStatus.COMPLETED)) {
      throw new BusinessException(HtpErrorCode.HTP_RESULTS_NOT_READY);
    }

    List<Long> sessionIds = steps.stream().map(step -> step.getDrawingSession().getId()).toList();
    Map<Long, DrawingAsset> finalAssets =
        drawingAssetRepository
            .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                sessionIds, DrawingAssetType.FINAL)
            .stream()
            .collect(
                Collectors.toMap(
                    asset -> asset.getDrawingSession().getId(),
                    Function.identity(),
                    (latest, ignored) -> latest));
    Map<Long, DrawingAnalysis> successfulObjectAnalyses =
        drawingAnalysisRepository
            .findByDrawingSessionIdInAndScopeOrderByDrawingSessionIdAscRequestedAtDescIdDesc(
                sessionIds, DrawingAnalysisScope.FINAL)
            .stream()
            .filter(analysis -> analysis.getTaskType() == DrawingAnalysisType.OBJECT_DETECTION)
            .filter(
                analysis ->
                    analysis.getState() == DrawingAnalysisState.SUCCESS
                        || analysis.getState() == DrawingAnalysisState.PARTIAL_SUCCESS)
            .collect(
                Collectors.toMap(
                    analysis -> analysis.getDrawingSession().getId(),
                    Function.identity(),
                    (latest, ignored) -> latest));
    boolean conversationsCompleted =
        sessionIds.stream()
            .allMatch(
                sessionId ->
                    conversationSessionRepository
                        .findByDrawingSessionId(sessionId)
                        .filter(ConversationSession::isCompleted)
                        .isPresent());
    if (finalAssets.size() != 3
        || successfulObjectAnalyses.size() != 3
        || !conversationsCompleted) {
      throw new BusinessException(HtpErrorCode.HTP_RESULTS_NOT_READY);
    }

    DrawingSession personSession = steps.get(2).getDrawingSession();
    DrawingAsset personFinal = finalAssets.get(personSession.getId());
    LocalDateTime requestedAt = now();
    try {
      if (assessment.getStatus() == HtpAssessmentStatus.FAILED
          && assessment.getReportId() != null) {
        reportRepository
            .findByIdForUpdate(assessment.getReportId())
            .ifPresent(report -> report.hideFailedVersion(requestedAt));
      }
      DrawingAnalysis reportAnalysis =
          drawingAnalysisRepository.saveAndFlush(
              DrawingAnalysis.pending(
                  personSession,
                  personFinal,
                  DrawingAnalysisType.ACTIVITY_REPORT,
                  idempotencyKey,
                  requestedAt));
      int reportVersion =
          reportRepository
              .findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(personSession.getId())
              .map(report -> report.getReportVersion() + 1)
              .orElse(1);
      Report report =
          reportRepository.saveAndFlush(
              Report.generating(personSession, reportAnalysis, reportVersion, requestedAt));
      assessment.startAnalysis(idempotencyKey, reportAnalysis.getId(), report.getId());
      eventPublisher.publishEvent(new ReportGenerationRequestedEvent(reportAnalysis.getId()));
      return completionResponse(assessment, reportAnalysis, report);
    } catch (RuntimeException exception) {
      if (exception instanceof BusinessException businessException) {
        throw businessException;
      }
      throw new BusinessException(HtpErrorCode.HTP_COMPLETION_CONFLICT, exception);
    }
  }

  /**
   * PERSON 단계에서 HTP 활동 전체를 대표하는 감정을 한 번 저장한다.
   *
   * @param assessmentId HTP 활동 식별자
   * @param request 선택 감정과 건너뛰기 여부
   * @return PERSON 그림 세션에 저장된 Reflection 결과
   * @throws BusinessException PERSON 단계가 아니거나 현재 상태에서 감정을 저장할 수 없는 경우
   */
  public DrawingReflectionResponse saveReflection(
      Long assessmentId, SaveDrawingReflectionRequest request) {
    HtpAssessment assessment = findAuthorizedForUpdate(assessmentId);
    HtpAssessmentStep currentStep = assessment.getCurrentStep();
    if (assessment.getStatus() != HtpAssessmentStatus.IN_PROGRESS
        || currentStep.getDrawingSubject() != HtpDrawingSubject.PERSON) {
      throw new BusinessException(HtpErrorCode.HTP_TRANSITION_NOT_ALLOWED);
    }
    return drawingReflectionService.save(currentStep.getDrawingSession().getId(), request);
  }

  /**
   * 접근 가능한 HTP 활동의 현재 단계를 조회한다.
   *
   * @param assessmentId HTP 활동 식별자
   * @return HTP 묶음과 현재 그림 단계
   */
  @Transactional(readOnly = true)
  public HtpAssessmentResponse get(Long assessmentId) {
    HtpAssessment assessment =
        htpAssessmentRepository
            .findDetailById(assessmentId)
            .orElseThrow(() -> new BusinessException(HtpErrorCode.HTP_ASSESSMENT_NOT_FOUND));
    authorize(assessment);
    return toResponse(assessment);
  }

  private HtpAssessment findAuthorizedForUpdate(Long assessmentId) {
    HtpAssessment assessment =
        htpAssessmentRepository
            .findDetailByIdForUpdate(assessmentId)
            .orElseThrow(() -> new BusinessException(HtpErrorCode.HTP_ASSESSMENT_NOT_FOUND));
    authorize(assessment);
    return assessment;
  }

  private void authorize(HtpAssessment assessment) {
    Long guardianId = currentUserResolver.requireUserId();
    accessValidator.requireChildAccess(guardianId, assessment.getChild().getId());
  }

  private void expire(HtpAssessment assessment, LocalDateTime expiredAt) {
    DrawingSession currentSession = assessment.getCurrentStep().getDrawingSession();
    if (currentSession.getSessionStatus() == DrawingSessionStatus.IN_PROGRESS) {
      currentSession.softDelete(expiredAt);
    }
    assessment.expire(expiredAt);
  }

  private HtpAssessmentResponse existingStart(
      HtpAssessment existing, StartHtpAssessmentRequest request) {
    DrawingSession session = existing.getSteps().get(0).getDrawingSession();
    if (!existing.getChild().getId().equals(request.childId())
        || session.getInputMethod() != request.inputMethod()) {
      throw new BusinessException(HtpErrorCode.IDEMPOTENCY_KEY_CONFLICT);
    }
    return toResponse(existing);
  }

  private void validateIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null) {
      throw new BusinessException(HtpErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    }
    if (idempotencyKey.length() < IDEMPOTENCY_KEY_MIN_LENGTH
        || idempotencyKey.length() > IDEMPOTENCY_KEY_MAX_LENGTH
        || idempotencyKey.isBlank()
        || CONTROL_CHARACTER.matcher(idempotencyKey).find()) {
      throw new BusinessException(HtpErrorCode.IDEMPOTENCY_KEY_INVALID);
    }
  }

  private LocalDateTime now() {
    return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
  }

  private HtpAssessmentResponse toResponse(HtpAssessment assessment) {
    HtpAssessmentStep step = assessment.getCurrentStep();
    DrawingSession session = step.getDrawingSession();
    boolean allStepsCompleted =
        step.getDrawingSubject() == HtpDrawingSubject.PERSON
            && session.getSessionStatus() == DrawingSessionStatus.COMPLETED;
    return new HtpAssessmentResponse(
        assessment.getId(),
        assessment.getStatus(),
        assessment.getExpiresAt().toInstant(ZoneOffset.UTC),
        new HtpAssessmentStepResponse(
            step.getStepOrder(),
            step.getDrawingSubject(),
            session.getId(),
            session.getSessionStatus(),
            session.getCurrentStage()),
        allStepsCompleted);
  }

  private HtpCompletionResponse completionResponse(HtpAssessment assessment) {
    if (assessment.getReportAnalysisId() == null || assessment.getReportId() == null) {
      throw new BusinessException(HtpErrorCode.HTP_COMPLETION_CONFLICT);
    }
    DrawingAnalysis analysis =
        drawingAnalysisRepository
            .findById(assessment.getReportAnalysisId())
            .orElseThrow(() -> new BusinessException(HtpErrorCode.HTP_COMPLETION_CONFLICT));
    Report report =
        reportRepository
            .findById(assessment.getReportId())
            .orElseThrow(() -> new BusinessException(HtpErrorCode.HTP_COMPLETION_CONFLICT));
    return completionResponse(assessment, analysis, report);
  }

  private HtpCompletionResponse completionResponse(
      HtpAssessment assessment, DrawingAnalysis analysis, Report report) {
    return new HtpCompletionResponse(
        assessment.getId(),
        assessment.getStatus(),
        analysis.getId(),
        analysis.getState(),
        report.getId(),
        report.getStatus());
  }
}
