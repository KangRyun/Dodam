package com.ssafy.b209.drawing.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.response.DrawingSessionHistoryItemResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionHistoryPageResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeSummaryResponse;
import com.ssafy.b209.drawing.dto.response.HtpDrawingHistoryResponse;
import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결 보호자가 아동의 그림 활동 기록 목록을 조회하는 읽기 전용 서비스다.
 *
 * <p>세션 페이지를 먼저 조회한 뒤 그 세션 식별자로 미리보기·선택 감정·분석 상태·리포트를 배치로 읽어 조립해 세션별 개별 조회를 피한다. 아동이 직접 선택한 감정만
 * 포함하며 AI 추정 감정·위험도·전문가 전용 정보는 조립 대상에서 제외한다.
 */
@Service
@Transactional(readOnly = true)
public class DrawingSessionHistoryQueryService {

  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingAssetRepository drawingAssetRepository;
  private final DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  private final DrawingAnalysisRepository drawingAnalysisRepository;
  private final ReportRepository reportRepository;
  private final HtpAssessmentRepository htpAssessmentRepository;
  private final DrawingAssetFileUrlFactory fileUrlFactory;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;

  /**
   * 활동 기록 목록 조립에 사용할 저장소와 인증·권한 경계를 구성한다.
   *
   * @param drawingSessionRepository 세션 페이지 조회 저장소
   * @param drawingAssetRepository 미리보기 이미지 배치 조회 저장소
   * @param drawingSessionEmotionRepository 선택 감정 배치 조회 저장소
   * @param drawingAnalysisRepository 분석 상태 배치 조회 저장소
   * @param reportRepository 리포트 배치 조회 저장소
   * @param fileUrlFactory 인증된 그림 파일 조회 URL 생성기
   * @param currentUserResolver Access Token에서 현재 보호자 ID를 제공하는 Resolver
   * @param accessValidator 보호자와 아동의 연결 관계를 검증하는 Validator
   */
  public DrawingSessionHistoryQueryService(
      DrawingSessionRepository drawingSessionRepository,
      DrawingAssetRepository drawingAssetRepository,
      DrawingSessionEmotionRepository drawingSessionEmotionRepository,
      DrawingAnalysisRepository drawingAnalysisRepository,
      ReportRepository reportRepository,
      HtpAssessmentRepository htpAssessmentRepository,
      DrawingAssetFileUrlFactory fileUrlFactory,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingAssetRepository = drawingAssetRepository;
    this.drawingSessionEmotionRepository = drawingSessionEmotionRepository;
    this.drawingAnalysisRepository = drawingAnalysisRepository;
    this.reportRepository = reportRepository;
    this.htpAssessmentRepository = htpAssessmentRepository;
    this.fileUrlFactory = fileUrlFactory;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
  }

  /**
   * 연결 보호자 권한을 검증하고 아동의 그림 활동 기록 한 페이지를 조립한다.
   *
   * <p>조회 과정에서 세션 상태를 변경하거나 외부 시스템을 호출하지 않으며, 조건에 맞는 활동이 없으면 빈 페이지를 반환한다.
   *
   * @param childId 조회 대상 아동 식별자
   * @param from 활동 시작일 하한(이상), 미지정이면 {@code null}
   * @param to 활동 시작일 상한(이하), 미지정이면 {@code null}
   * @param drawingTypeCode 그림 활동 유형 코드 필터, 미지정이면 {@code null}
   * @param sessionStatus 세션 상태 필터, 미지정이면 {@code null}
   * @param reportStatus 최신 리포트 상태 필터, 미지정이면 {@code null}
   * @param pageable 페이지와 정렬(시작·완료 시각) 조건
   * @return 활동 기록 목록과 페이지 메타데이터
   */
  public DrawingSessionHistoryPageResponse getHistory(
      Long childId,
      LocalDate from,
      LocalDate to,
      String drawingTypeCode,
      DrawingSessionStatus sessionStatus,
      ReportStatus reportStatus,
      Pageable pageable) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireChildAccess(guardianUserId, childId);

    LocalDateTime fromInclusive = from == null ? null : from.atStartOfDay();
    LocalDateTime toExclusive = toExclusive(to);

    Page<DrawingSession> page =
        drawingSessionRepository.findHistoryPage(
            childId,
            fromInclusive,
            toExclusive,
            drawingTypeCode,
            sessionStatus,
            reportStatus,
            pageable);
    List<DrawingSession> sessions = page.getContent();
    List<Long> sessionIds = sessions.stream().map(DrawingSession::getId).toList();
    Map<Long, HtpAssessment> htpByRepresentativeSession = loadHtpAssessments(sessionIds);
    List<Long> imageSessionIds =
        htpByRepresentativeSession.values().stream()
            .flatMap(assessment -> assessment.getSteps().stream())
            .map(step -> step.getDrawingSession().getId())
            .distinct()
            .toList();
    List<Long> thumbnailSessionIds =
        java.util.stream.Stream.concat(sessionIds.stream(), imageSessionIds.stream())
            .distinct()
            .toList();

    Map<Long, String> thumbnailUrlBySession = loadThumbnailUrls(thumbnailSessionIds);
    Map<Long, List<DrawingEmotionCode>> emotionsBySession = loadSelectedEmotions(sessionIds);
    Map<Long, DrawingAnalysisStatus> analysisStatusBySession = loadLatestAnalysisStatus(sessionIds);
    Map<Long, Report> latestReportBySession = loadLatestReports(sessionIds);

    List<DrawingSessionHistoryItemResponse> content = new ArrayList<>(sessions.size());
    for (DrawingSession session : sessions) {
      Long sessionId = session.getId();
      Report report = latestReportBySession.get(sessionId);
      HtpAssessment htpAssessment = htpByRepresentativeSession.get(sessionId);
      content.add(
          new DrawingSessionHistoryItemResponse(
              sessionId,
              thumbnailUrlBySession.get(sessionId),
              toDrawingTypeSummary(session.getDrawingType()),
              session.getTitle(),
              session.getInputMethod(),
              session.getSessionStatus(),
              session.getCurrentStage(),
              emotionsBySession.getOrDefault(sessionId, List.of()),
              analysisStatusBySession.get(sessionId),
              htpAssessment == null
                  ? (report == null ? null : report.getId())
                  : htpAssessment.getReportId(),
              report == null ? null : report.getStatus(),
              (htpAssessment == null ? session.getStartedAt() : htpAssessment.getCreatedAt())
                  .toInstant(ZoneOffset.UTC),
              toNullableInstant(
                  htpAssessment == null
                      ? session.getCompletedAt()
                      : htpAssessment.getCompletedAt()),
              htpAssessment == null ? "GENERAL" : "HTP",
              htpAssessment == null ? null : htpAssessment.getId(),
              htpAssessment == null ? null : htpAssessment.getStatus(),
              toHtpDrawings(htpAssessment, thumbnailUrlBySession)));
    }

    return new DrawingSessionHistoryPageResponse(
        content,
        page.getNumber(),
        page.getSize(),
        page.getTotalElements(),
        page.getTotalPages(),
        page.isFirst(),
        page.isLast(),
        page.hasNext());
  }

  private Map<Long, HtpAssessment> loadHtpAssessments(List<Long> representativeSessionIds) {
    Map<Long, HtpAssessment> byRepresentativeSession = new LinkedHashMap<>();
    if (representativeSessionIds.isEmpty()) {
      return byRepresentativeSession;
    }
    for (HtpAssessment assessment :
        htpAssessmentRepository.findByStepDrawingSessionIdIn(representativeSessionIds)) {
      HtpAssessmentStep representativeStep =
          assessment.getSteps().stream()
              .max(java.util.Comparator.comparingInt(HtpAssessmentStep::getStepOrder))
              .orElseThrow();
      byRepresentativeSession.put(representativeStep.getDrawingSession().getId(), assessment);
    }
    return byRepresentativeSession;
  }

  private List<HtpDrawingHistoryResponse> toHtpDrawings(
      HtpAssessment assessment, Map<Long, String> thumbnailUrlBySession) {
    if (assessment == null) {
      return List.of();
    }
    // 엔티티의 stepOrder 정렬을 그대로 사용해 HOUSE, TREE, PERSON 순서를 보장한다.
    return assessment.getSteps().stream()
        .map(
            step ->
                new HtpDrawingHistoryResponse(
                    step.getDrawingSubject(),
                    step.getDrawingSession().getId(),
                    thumbnailUrlBySession.get(step.getDrawingSession().getId())))
        .toList();
  }

  private Map<Long, String> loadThumbnailUrls(List<Long> sessionIds) {
    Map<Long, String> bySession = new LinkedHashMap<>();
    if (sessionIds.isEmpty()) {
      return bySession;
    }
    for (DrawingAsset asset :
        drawingAssetRepository
            .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                sessionIds, DrawingAssetType.THUMBNAIL)) {
      bySession.putIfAbsent(
          asset.getDrawingSession().getId(), fileUrlFactory.create(asset.getId()));
    }
    List<Long> sessionsWithoutThumbnail =
        sessionIds.stream().filter(sessionId -> !bySession.containsKey(sessionId)).toList();
    if (sessionsWithoutThumbnail.isEmpty()) {
      return bySession;
    }
    for (DrawingAsset asset :
        drawingAssetRepository
            .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                sessionsWithoutThumbnail, DrawingAssetType.FINAL)) {
      bySession.putIfAbsent(
          asset.getDrawingSession().getId(), fileUrlFactory.create(asset.getId()));
    }
    return bySession;
  }

  private Map<Long, List<DrawingEmotionCode>> loadSelectedEmotions(List<Long> sessionIds) {
    Map<Long, List<DrawingEmotionCode>> bySession = new LinkedHashMap<>();
    if (sessionIds.isEmpty()) {
      return bySession;
    }
    for (DrawingSessionEmotion emotion :
        drawingSessionEmotionRepository
            .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(sessionIds)) {
      bySession
          .computeIfAbsent(emotion.getDrawingSession().getId(), key -> new ArrayList<>())
          .add(emotion.getEmotionCode());
    }
    return bySession;
  }

  private Map<Long, DrawingAnalysisStatus> loadLatestAnalysisStatus(List<Long> sessionIds) {
    Map<Long, DrawingAnalysisStatus> bySession = new LinkedHashMap<>();
    if (sessionIds.isEmpty()) {
      return bySession;
    }
    for (DrawingAnalysis analysis :
        drawingAnalysisRepository
            .findByDrawingSessionIdInAndScopeOrderByDrawingSessionIdAscRequestedAtDescIdDesc(
                sessionIds, DrawingAnalysisScope.FINAL)) {
      bySession.putIfAbsent(
          analysis.getDrawingSession().getId(), DrawingAnalysisStatus.from(analysis.getState()));
    }
    return bySession;
  }

  private Map<Long, Report> loadLatestReports(List<Long> sessionIds) {
    Map<Long, Report> bySession = new LinkedHashMap<>();
    if (sessionIds.isEmpty()) {
      return bySession;
    }
    for (Report report :
        reportRepository.findByDrawingSessionIdInOrderByDrawingSessionIdAscCreatedAtDescIdDesc(
            sessionIds)) {
      bySession.putIfAbsent(report.getDrawingSession().getId(), report);
    }
    return bySession;
  }

  private DrawingTypeSummaryResponse toDrawingTypeSummary(DrawingType type) {
    return new DrawingTypeSummaryResponse(type.getId(), type.getCode(), type.getName());
  }

  private Instant toNullableInstant(LocalDateTime dateTime) {
    return dateTime == null ? null : dateTime.toInstant(ZoneOffset.UTC);
  }

  private LocalDateTime toExclusive(LocalDate to) {
    if (to == null) {
      return null;
    }
    try {
      return to.plusDays(1).atStartOfDay();
    } catch (DateTimeException exception) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }
}
