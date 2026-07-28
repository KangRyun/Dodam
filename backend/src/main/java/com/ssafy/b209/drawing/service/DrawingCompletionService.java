package com.ssafy.b209.drawing.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.CompleteDrawingSessionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingCompletionResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.repository.ReportRepository;
import com.ssafy.b209.report.service.ReportGenerationRequestedEvent;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Optional;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 그림 활동의 최종 분석과 선택적 리포트 생성을 멱등하게 접수한다.
 *
 * <p>세션 잠금 안에서 사전 조건을 검증하고 분석·리포트·REPORTING 전이를 하나의 Transaction으로 저장한다. 실제 AI 및 리포트 생성 작업은 호출하지
 * 않는다.
 */
@Service
public class DrawingCompletionService {

  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final DrawingSessionRepository sessionRepository;
  private final DrawingAssetRepository assetRepository;
  private final ConversationSessionRepository conversationRepository;
  private final DrawingAnalysisRepository analysisRepository;
  private final ReportRepository reportRepository;
  private final ApplicationEventPublisher eventPublisher;
  private final Clock clock;

  /**
   * 완료 접수에 필요한 인증, 그림, 대화, 분석과 리포트 저장 의존성을 구성한다.
   *
   * @param currentUserResolver 현재 인증 사용자 Resolver
   * @param accessValidator 보호자와 그림 활동의 연결 관계 Validator
   * @param sessionRepository 그림 활동 세션 잠금 Repository
   * @param assetRepository 최종 그림 조회 Repository
   * @param conversationRepository 대화 상태 조회 Repository
   * @param analysisRepository 최종 분석 저장 Repository
   * @param reportRepository 리포트 생성 접수 Repository
   * @param eventPublisher 커밋 후 리포트 생성을 요청하는 이벤트 발행기
   * @param clock 서버 접수 시각을 제공하는 UTC Clock
   */
  public DrawingCompletionService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      DrawingSessionRepository sessionRepository,
      DrawingAssetRepository assetRepository,
      ConversationSessionRepository conversationRepository,
      DrawingAnalysisRepository analysisRepository,
      ReportRepository reportRepository,
      ApplicationEventPublisher eventPublisher,
      Clock clock) {
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.sessionRepository = sessionRepository;
    this.assetRepository = assetRepository;
    this.conversationRepository = conversationRepository;
    this.analysisRepository = analysisRepository;
    this.reportRepository = reportRepository;
    this.eventPublisher = eventPublisher;
    this.clock = clock;
  }

  /**
   * 최종 분석과 선택적 리포트 생성을 접수하고 그림 활동을 REPORTING 단계로 전환한다.
   *
   * @param drawingSessionId 완료 접수 대상 그림 활동 세션 식별자
   * @param idempotencyKey 재시도를 식별하는 {@code Idempotency-Key} Header 값
   * @param request 대화 생략 및 리포트 요청 여부
   * @return 새로 생성했거나 멱등하게 조회한 완료 접수 상태
   * @throws BusinessException 권한, 사전 조건, 멱등성 또는 저장 충돌이 발생한 경우
   */
  @Transactional
  public DrawingCompletionResponse complete(
      Long drawingSessionId, String idempotencyKey, CompleteDrawingSessionRequest request) {
    validateIdempotencyKey(idempotencyKey);
    validateReportRequest(request);
    Long guardianId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianId, drawingSessionId);
    DrawingSession session =
        sessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    Optional<ConversationSession> conversation =
        conversationRepository.findByDrawingSessionId(drawingSessionId);

    Optional<DrawingAnalysis> existing = analysisRepository.findByRequestId(idempotencyKey);
    if (existing.isPresent()) {
      return idempotentResponse(existing.get(), session, request, conversation);
    }

    validateNewRequest(session, request, conversation);
    DrawingAsset finalAsset =
        assetRepository
            .findFirstByDrawingSessionIdAndAssetTypeOrderByAssetVersionDesc(
                drawingSessionId, DrawingAssetType.FINAL)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.FINAL_ASSET_REQUIRED));
    LocalDateTime requestedAt = LocalDateTime.now(clock);
    try {
      DrawingAnalysis analysis =
          analysisRepository.saveAndFlush(
              DrawingAnalysis.pending(
                  session,
                  finalAsset,
                  DrawingAnalysisType.ACTIVITY_REPORT,
                  idempotencyKey,
                  requestedAt));
      Report report =
          reportRepository.saveAndFlush(Report.generating(session, analysis, 1, requestedAt));
      session.startReporting();
      eventPublisher.publishEvent(new ReportGenerationRequestedEvent(analysis.getId()));
      return response(session, analysis, report);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(DrawingErrorCode.DRAWING_COMPLETION_CONFLICT, exception);
    }
  }

  private DrawingCompletionResponse idempotentResponse(
      DrawingAnalysis analysis,
      DrawingSession session,
      CompleteDrawingSessionRequest request,
      Optional<ConversationSession> conversation) {
    boolean sameSession =
        analysis.getDrawingSession() != null
            && analysis.getDrawingSession().getId().equals(session.getId());
    if (!sameSession || analysis.getTaskType() != DrawingAnalysisType.ACTIVITY_REPORT) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT);
    }
    if (!matchesConversation(request, conversation)) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT);
    }
    Optional<Report> report = reportRepository.findByAnalysisId(analysis.getId());
    if (report.isEmpty()) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT);
    }
    return response(session, analysis, report.get());
  }

  private void validateNewRequest(
      DrawingSession session,
      CompleteDrawingSessionRequest request,
      Optional<ConversationSession> conversation) {
    if (!session.canRequestCompletion()) {
      if (session.getCurrentStage() == DrawingStage.REPORTING
          || session.getCurrentStage() == DrawingStage.COMPLETED
          || session.getSessionStatus() == DrawingSessionStatus.COMPLETED) {
        throw new BusinessException(DrawingErrorCode.DRAWING_SESSION_ALREADY_COMPLETED);
      }
      throw new BusinessException(DrawingErrorCode.REFLECTION_REQUIRED);
    }
    validateConversation(request, conversation);
  }

  private void validateConversation(
      CompleteDrawingSessionRequest request, Optional<ConversationSession> conversation) {
    if (!matchesConversation(request, conversation)) {
      throw new BusinessException(DrawingErrorCode.DRAWING_CONVERSATION_NOT_COMPLETED);
    }
  }

  private boolean matchesConversation(
      CompleteDrawingSessionRequest request, Optional<ConversationSession> conversation) {
    return Boolean.TRUE.equals(request.conversationSkipped())
        ? conversation.isEmpty()
        : conversation.filter(ConversationSession::isCompleted).isPresent();
  }

  private DrawingCompletionResponse response(
      DrawingSession session, DrawingAnalysis analysis, Report report) {
    return new DrawingCompletionResponse(
        session.getId(),
        session.getSessionStatus(),
        session.getCurrentStage(),
        analysis.getId(),
        analysis.getState(),
        report.getId(),
        report.getStatus());
  }

  private void validateReportRequest(CompleteDrawingSessionRequest request) {
    if (!Boolean.TRUE.equals(request.requestReport())) {
      throw new BusinessException(DrawingErrorCode.REPORT_REQUEST_REQUIRED);
    }
  }

  private void validateIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null || idempotencyKey.isBlank()) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    }
    int length = idempotencyKey.length();
    if (length < IDEMPOTENCY_KEY_MIN_LENGTH
        || length > IDEMPOTENCY_KEY_MAX_LENGTH
        || idempotencyKey.chars().anyMatch(Character::isISOControl)) {
      throw new BusinessException(DrawingErrorCode.IDEMPOTENCY_KEY_INVALID);
    }
  }
}
