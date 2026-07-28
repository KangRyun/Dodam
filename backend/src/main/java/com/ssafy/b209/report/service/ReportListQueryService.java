package com.ssafy.b209.report.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.service.DrawingAssetFileUrlFactory;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportListDrawingTypeResponse;
import com.ssafy.b209.report.dto.ReportListItemResponse;
import com.ssafy.b209.report.dto.ReportListPageResponse;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.DateTimeException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자 권한을 확인하고 아동별 관찰 리포트 목록을 조립하는 읽기 서비스다.
 *
 * <p>페이지의 세션 식별자를 기준으로 썸네일과 선택 감정을 배치 조회하여 리포트 수에 비례하는 추가 쿼리를 방지한다.
 */
@Service
@Transactional(readOnly = true)
public class ReportListQueryService {

  private final ReportRepository reportRepository;
  private final DrawingAssetRepository drawingAssetRepository;
  private final DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  private final DrawingAssetFileUrlFactory fileUrlFactory;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;

  /**
   * 리포트 목록 조회에 필요한 저장소와 인증 경계를 구성한다.
   *
   * @param reportRepository 리포트 페이지 조회 저장소
   * @param drawingAssetRepository 썸네일 배치 조회 저장소
   * @param drawingSessionEmotionRepository 선택 감정 배치 조회 저장소
   * @param fileUrlFactory 인증된 그림 파일 조회 URL 생성기
   * @param currentUserResolver 현재 보호자 식별자 Resolver
   * @param accessValidator 보호자-아동 연결 관계 Validator
   */
  public ReportListQueryService(
      ReportRepository reportRepository,
      DrawingAssetRepository drawingAssetRepository,
      DrawingSessionEmotionRepository drawingSessionEmotionRepository,
      DrawingAssetFileUrlFactory fileUrlFactory,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this.reportRepository = reportRepository;
    this.drawingAssetRepository = drawingAssetRepository;
    this.drawingSessionEmotionRepository = drawingSessionEmotionRepository;
    this.fileUrlFactory = fileUrlFactory;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
  }

  /**
   * 연결 보호자가 조회할 수 있는 아동의 리포트 페이지를 반환한다.
   *
   * @param childId 조회 대상 아동 식별자
   * @param from 활동일 하한이며 없으면 {@code null}
   * @param to 활동일 상한이며 없으면 {@code null}
   * @param drawingTypeCode 그림 유형 코드이며 없으면 {@code null}
   * @param reportStatus 리포트 상태이며 없으면 {@code null}
   * @param pageable 페이지 조건
   * @return 리포트 목록과 페이지 메타데이터
   */
  public ReportListPageResponse getReports(
      Long childId,
      LocalDate from,
      LocalDate to,
      String drawingTypeCode,
      ReportStatus reportStatus,
      Pageable pageable) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireChildAccess(guardianUserId, childId);

    Page<Report> page =
        reportRepository.findVisiblePage(
            childId,
            from == null ? null : from.atStartOfDay(),
            toExclusive(to),
            drawingTypeCode,
            reportStatus,
            pageable);
    List<Long> sessionIds =
        page.getContent().stream().map(report -> report.getDrawingSession().getId()).toList();
    Map<Long, String> thumbnailUrls = loadThumbnailUrls(sessionIds);
    Map<Long, List<String>> emotions = loadSelectedEmotions(sessionIds);

    List<ReportListItemResponse> content =
        page.getContent().stream().map(report -> toItem(report, thumbnailUrls, emotions)).toList();
    return new ReportListPageResponse(
        content,
        page.getNumber(),
        page.getSize(),
        page.getTotalElements(),
        page.getTotalPages(),
        page.isFirst(),
        page.isLast(),
        page.hasNext());
  }

  private ReportListItemResponse toItem(
      Report report, Map<Long, String> thumbnailUrls, Map<Long, List<String>> emotionsBySession) {
    DrawingSession session = report.getDrawingSession();
    DrawingType type = session.getDrawingType();
    Long sessionId = session.getId();
    String title =
        session.getTitle() == null || session.getTitle().isBlank()
            ? type.getName()
            : session.getTitle();
    return new ReportListItemResponse(
        report.getId(),
        report.getReportVersion(),
        sessionId,
        new ReportListDrawingTypeResponse(type.getId(), type.getCode(), type.getName()),
        title,
        thumbnailUrls.get(sessionId),
        session.getStartedAt().toLocalDate(),
        durationMs(session),
        emotionsBySession.getOrDefault(sessionId, List.of()),
        report.getStatus(),
        false);
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

  private Map<Long, List<String>> loadSelectedEmotions(List<Long> sessionIds) {
    Map<Long, List<String>> bySession = new LinkedHashMap<>();
    if (sessionIds.isEmpty()) {
      return bySession;
    }
    for (DrawingSessionEmotion emotion :
        drawingSessionEmotionRepository
            .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(sessionIds)) {
      bySession
          .computeIfAbsent(emotion.getDrawingSession().getId(), ignored -> new ArrayList<>())
          .add(emotion.getEmotionCode().name());
    }
    return bySession;
  }

  private Long durationMs(DrawingSession session) {
    LocalDateTime completedAt = session.getCompletedAt();
    if (completedAt == null) {
      return null;
    }
    long duration = java.time.Duration.between(session.getStartedAt(), completedAt).toMillis();
    return duration < 0 ? null : duration;
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
