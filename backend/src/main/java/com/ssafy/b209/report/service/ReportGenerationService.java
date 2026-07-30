package com.ssafy.b209.report.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.service.StageFinalImageFinder;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportGenerationStatusResponse;
import com.ssafy.b209.report.exception.ReportDetailErrorCode;
import com.ssafy.b209.report.exception.ReportGenerationErrorCode;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Optional;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자용 관찰 리포트 생성 상태 조회와 실패 작업 재접수를 조율한다.
 *
 * <p>재생성은 기존 Report와 Analysis를 덮어쓰지 않고 다음 버전의 Report와 연결된 새 Analysis를 만든다. Transaction이 Commit된 뒤
 * 기존 생성 Listener가 새 Analysis를 처리한다.
 *
 * <p>재생성 입력 그림은 {@link StageFinalImageFinder}가 확정한다. Canvas 세션은 {@code FINAL} 그림이 있어야 하고, 사진 업로드
 * 세션은 업로드한 원본이 최종 그림이므로 최초 생성과 같은 그림으로 재시도할 수 있다.
 */
@Service
public class ReportGenerationService {

  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;

  private final GuardianResourceAccessRepository accessRepository;
  private final ReportRepository reportRepository;
  private final DrawingSessionRepository sessionRepository;
  private final StageFinalImageFinder stageFinalImageFinder;
  private final DrawingAnalysisRepository analysisRepository;
  private final ApplicationEventPublisher eventPublisher;
  private final Clock clock;

  /**
   * 리포트 상태 조회와 재생성에 필요한 저장소 및 이벤트 발행기를 구성한다.
   *
   * @param accessRepository 보호자와 Drawing Session의 연결 관계 조회 저장소
   * @param reportRepository 리포트 저장소
   * @param sessionRepository Drawing Session 잠금 저장소
   * @param stageFinalImageFinder 세션의 최종 그림을 확정하는 경계
   * @param analysisRepository 최종 분석 저장소
   * @param eventPublisher Commit 이후 리포트 생성 요청을 전달할 이벤트 발행기
   * @param clock 재생성 접수 시각을 제공하는 Clock
   */
  public ReportGenerationService(
      GuardianResourceAccessRepository accessRepository,
      ReportRepository reportRepository,
      DrawingSessionRepository sessionRepository,
      StageFinalImageFinder stageFinalImageFinder,
      DrawingAnalysisRepository analysisRepository,
      ApplicationEventPublisher eventPublisher,
      Clock clock) {
    this.accessRepository = accessRepository;
    this.reportRepository = reportRepository;
    this.sessionRepository = sessionRepository;
    this.stageFinalImageFinder = stageFinalImageFinder;
    this.analysisRepository = analysisRepository;
    this.eventPublisher = eventPublisher;
    this.clock = clock;
  }

  /**
   * 리포트의 생성 상태와 최신 실패 작업의 재시도 가능 여부를 조회한다.
   *
   * @param guardianUserId 인증된 보호자 식별자
   * @param reportId 조회할 리포트 식별자
   * @return 폴링에 필요한 경량 생성 상태
   * @throws BusinessException 리포트가 없거나 보호자 접근 권한이 없는 경우
   */
  @Transactional(readOnly = true)
  public ReportGenerationStatusResponse getStatus(Long guardianUserId, Long reportId) {
    Report report =
        reportRepository
            .findById(reportId)
            .orElseThrow(() -> new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND));
    requireAccess(guardianUserId, report);
    Report latest =
        reportRepository
            .findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(
                report.getDrawingSession().getId())
            .orElse(report);
    return response(report, isRetryable(report, latest));
  }

  /**
   * 최신 FAILED 리포트를 다음 버전으로 재접수한다.
   *
   * @param guardianUserId 인증된 보호자 식별자
   * @param reportId 재생성할 실패 리포트 식별자
   * @param idempotencyKey 중복 재접수를 방지하는 요청 식별자
   * @return 새로 접수됐거나 동일 Key로 이미 접수된 리포트 생성 상태
   * @throws BusinessException 권한, 상태, 멱등성 또는 동시성 검증에 실패한 경우
   */
  @Transactional
  public ReportGenerationStatusResponse regenerate(
      Long guardianUserId, Long reportId, String idempotencyKey) {
    validateIdempotencyKey(idempotencyKey);
    Report source =
        reportRepository
            .findByIdForUpdate(reportId)
            .orElseThrow(() -> new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND));
    requireAccess(guardianUserId, source);

    Optional<DrawingAnalysis> existing = analysisRepository.findByRequestId(idempotencyKey);
    if (existing.isPresent()) {
      return idempotentResponse(source, existing.get());
    }

    Long sessionId = source.getDrawingSession().getId();
    Report latest =
        reportRepository
            .findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(sessionId)
            .orElse(source);
    if (!isRetryable(source, latest)) {
      throw new BusinessException(ReportGenerationErrorCode.REGENERATION_NOT_ALLOWED);
    }

    DrawingSession session =
        sessionRepository
            .findNotDeletedByIdForUpdate(sessionId)
            .orElseThrow(() -> new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND));
    DrawingAsset finalAsset =
        stageFinalImageFinder
            .find(session)
            .orElseThrow(
                () -> new BusinessException(ReportGenerationErrorCode.FINAL_ASSET_REQUIRED));
    LocalDateTime requestedAt = LocalDateTime.now(clock);

    try {
      DrawingAnalysis analysis =
          analysisRepository.saveAndFlush(
              DrawingAnalysis.pendingRetry(
                  source.getAnalysis(), finalAsset, idempotencyKey, requestedAt));
      Report report =
          reportRepository.saveAndFlush(
              Report.generating(session, analysis, source.getReportVersion() + 1, requestedAt));
      session.restartReporting();
      eventPublisher.publishEvent(new ReportGenerationRequestedEvent(analysis.getId()));
      return response(report, false);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(ReportGenerationErrorCode.REGENERATION_CONFLICT, exception);
    }
  }

  private ReportGenerationStatusResponse idempotentResponse(
      Report source, DrawingAnalysis existing) {
    DrawingAnalysis retrySource = existing.getRetryOfAnalysis();
    if (retrySource == null || !source.getAnalysis().getId().equals(retrySource.getId())) {
      throw new BusinessException(ReportGenerationErrorCode.IDEMPOTENCY_KEY_CONFLICT);
    }
    Report report =
        reportRepository
            .findByAnalysisId(existing.getId())
            .orElseThrow(
                () -> new BusinessException(ReportGenerationErrorCode.IDEMPOTENCY_KEY_CONFLICT));
    return response(report, false);
  }

  private void requireAccess(Long guardianUserId, Report report) {
    if (!accessRepository.hasDrawingSessionAccess(
        guardianUserId, report.getDrawingSession().getId())) {
      throw new BusinessException(ReportDetailErrorCode.REPORT_ACCESS_DENIED);
    }
  }

  private boolean isRetryable(Report report, Report latest) {
    return report.getStatus() == ReportStatus.FAILED && report.getId().equals(latest.getId());
  }

  private ReportGenerationStatusResponse response(Report report, boolean retryable) {
    return new ReportGenerationStatusResponse(
        report.getId(),
        report.getDrawingSession().getId(),
        report.getAnalysis().getId(),
        report.getReportVersion(),
        report.getStatus(),
        retryable,
        report.getFailureReason(),
        report.getCreatedAt(),
        report.getUpdatedAt(),
        report.getFailedAt());
  }

  private void validateIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null || idempotencyKey.isBlank()) {
      throw new BusinessException(ReportGenerationErrorCode.IDEMPOTENCY_KEY_REQUIRED);
    }
    int length = idempotencyKey.length();
    if (length < IDEMPOTENCY_KEY_MIN_LENGTH
        || length > IDEMPOTENCY_KEY_MAX_LENGTH
        || idempotencyKey.chars().anyMatch(Character::isISOControl)) {
      throw new BusinessException(ReportGenerationErrorCode.IDEMPOTENCY_KEY_INVALID);
    }
  }
}
