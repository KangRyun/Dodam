package com.ssafy.b209.report.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.drawing.service.DrawingAssetFileUrlFactory;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.ReportActivitySummaryView;
import com.ssafy.b209.report.domain.ReportConversationSummaryView;
import com.ssafy.b209.report.domain.ReportDetailView;
import com.ssafy.b209.report.domain.ReportDrawingAssetView;
import com.ssafy.b209.report.domain.ReportDrawingEmotionView;
import com.ssafy.b209.report.domain.ReportDrawingSessionView;
import com.ssafy.b209.report.domain.ReportDrawingTypeView;
import com.ssafy.b209.report.domain.ReportKeyConversationView;
import com.ssafy.b209.report.dto.ReportActivityFactsResponse;
import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportConversationSummaryResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDrawingResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
import com.ssafy.b209.report.dto.ReportUtteranceResponse;
import com.ssafy.b209.report.exception.ReportDetailErrorCode;
import com.ssafy.b209.report.repository.ReportActivityNoteViewRepository;
import com.ssafy.b209.report.repository.ReportActivitySummaryViewRepository;
import com.ssafy.b209.report.repository.ReportConversationSummaryViewRepository;
import com.ssafy.b209.report.repository.ReportDetailViewRepository;
import com.ssafy.b209.report.repository.ReportDetectedObjectRow;
import com.ssafy.b209.report.repository.ReportDetectedObjectViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingAssetViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingEmotionViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingSessionViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingTypeViewRepository;
import com.ssafy.b209.report.repository.ReportDrawnItemRepository;
import com.ssafy.b209.report.repository.ReportFollowUpGuideViewRepository;
import com.ssafy.b209.report.repository.ReportKeyConversationViewRepository;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * REPORT-02 보호자용 관찰 리포트 상세 조회의 소유권 검증과 정규화된 리포트 데이터 조립을 담당하는 읽기 전용 서비스다.
 *
 * <p>리포트가 연결된 그림 활동 세션의 아동에 대한 보호자 접근 권한을 확인한 뒤, 리포트와 활동·대화·분석 하위 데이터를 읽기 전용 프로젝션으로 조립한다. 보호자 안전
 * 규칙에 따라 AI 추정 감정·확률, 위험도 점수, 전문가 전용 관찰 특징({@code report_observed_features}), 내부 프롬프트·지표는 조회 대상에서
 * 제외해 응답에 노출하지 않는다.
 */
@Service
@Transactional(readOnly = true)
public class ReportDetailQueryService {

  private static final String FINAL_ASSET_TYPE = "FINAL";
  private static final String THUMBNAIL_ASSET_TYPE = "THUMBNAIL";
  private static final String UPLOADED_ASSET_TYPE = "UPLOADED";
  private static final BigDecimal LEGACY_DETECTION_MIN_CONFIDENCE = new BigDecimal("0.50");

  private final GuardianResourceAccessRepository guardianAccessRepository;
  private final ReportDetailViewRepository reportRepository;
  private final ReportDrawingSessionViewRepository drawingSessionRepository;
  private final ReportDrawingTypeViewRepository drawingTypeRepository;
  private final ReportDrawingAssetViewRepository assetRepository;
  private final ReportDrawingEmotionViewRepository emotionRepository;
  private final ReportActivitySummaryViewRepository activitySummaryRepository;
  private final ReportActivityNoteViewRepository activityNoteRepository;
  private final ReportKeyConversationViewRepository keyConversationRepository;
  private final ReportFollowUpGuideViewRepository followUpGuideRepository;
  private final ReportConversationSummaryViewRepository conversationSummaryRepository;
  private final ReportDetectedObjectViewRepository detectedObjectRepository;
  private final ReportDrawnItemRepository drawnItemRepository;
  private final DrawingAssetFileUrlFactory fileUrlFactory;

  /**
   * 리포트 상세 조회 Use Case 의존성을 생성한다.
   *
   * @param guardianAccessRepository 보호자-아동-그림 활동 접근 관계 조회 경계
   * @param reportRepository 리포트 헤더 조회 경계
   * @param drawingSessionRepository 그림 활동 세션 조회 경계
   * @param drawingTypeRepository 그림 활동 유형 조회 경계
   * @param assetRepository 그림 파일 URL 조회 경계
   * @param emotionRepository 아동 선택 감정 조회 경계
   * @param activitySummaryRepository 활동·대화 집계 요약 조회 경계
   * @param activityNoteRepository 활동 주의사항 조회 경계
   * @param keyConversationRepository 대표 대화 Snapshot 조회 경계
   * @param followUpGuideRepository 보호자 후속 안내 조회 경계
   * @param conversationSummaryRepository 대화 요약 대체 출처 조회 경계
   * @param detectedObjectRepository 과거 리포트의 탐지 객체명 폴백 조회 경계
   * @param drawnItemRepository 최신 AI 관찰 서술 기반 '그린 것' 조회 경계
   * @param fileUrlFactory 인증된 그림 파일 조회 URL 생성기
   */
  public ReportDetailQueryService(
      GuardianResourceAccessRepository guardianAccessRepository,
      ReportDetailViewRepository reportRepository,
      ReportDrawingSessionViewRepository drawingSessionRepository,
      ReportDrawingTypeViewRepository drawingTypeRepository,
      ReportDrawingAssetViewRepository assetRepository,
      ReportDrawingEmotionViewRepository emotionRepository,
      ReportActivitySummaryViewRepository activitySummaryRepository,
      ReportActivityNoteViewRepository activityNoteRepository,
      ReportKeyConversationViewRepository keyConversationRepository,
      ReportFollowUpGuideViewRepository followUpGuideRepository,
      ReportConversationSummaryViewRepository conversationSummaryRepository,
      ReportDetectedObjectViewRepository detectedObjectRepository,
      ReportDrawnItemRepository drawnItemRepository,
      DrawingAssetFileUrlFactory fileUrlFactory) {
    this.guardianAccessRepository = guardianAccessRepository;
    this.reportRepository = reportRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingTypeRepository = drawingTypeRepository;
    this.assetRepository = assetRepository;
    this.emotionRepository = emotionRepository;
    this.activitySummaryRepository = activitySummaryRepository;
    this.activityNoteRepository = activityNoteRepository;
    this.keyConversationRepository = keyConversationRepository;
    this.followUpGuideRepository = followUpGuideRepository;
    this.conversationSummaryRepository = conversationSummaryRepository;
    this.detectedObjectRepository = detectedObjectRepository;
    this.drawnItemRepository = drawnItemRepository;
    this.fileUrlFactory = fileUrlFactory;
  }

  /**
   * 보호자 접근 권한을 검증하고 리포트 상세 응답을 조립한다.
   *
   * <p>생성 중이거나 실패한 리포트는 하위 데이터가 비어 있어 각 섹션이 빈 목록·{@code null}로 조립되며, 별도 오류 없이 현재 상태를 그대로 반환한다.
   *
   * @param guardianUserId 인증에서 해석한 보호자 식별자
   * @param reportId URL 리포트 식별자
   * @return 보호자에게 노출 가능한 리포트 상세 응답
   * @throws BusinessException 리포트가 없거나 숨김이면 {@code REPORT_NOT_FOUND}, 보호자 접근 권한이 없으면 {@code
   *     REPORT_ACCESS_DENIED}
   */
  public ReportDetailResponse getReport(Long guardianUserId, Long reportId) {
    ReportDetailView report =
        reportRepository
            .findById(reportId)
            .orElseThrow(() -> new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND));
    if (report.isHidden()) {
      throw new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND);
    }
    if (!guardianAccessRepository.hasDrawingSessionAccess(
        guardianUserId, report.getDrawingSessionId())) {
      throw new BusinessException(ReportDetailErrorCode.REPORT_ACCESS_DENIED);
    }

    ReportDrawingSessionView session =
        drawingSessionRepository
            .findById(report.getDrawingSessionId())
            .orElseThrow(() -> new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND));

    return new ReportDetailResponse(
        report.getId(),
        report.getReportVersion(),
        report.getStatus().name(),
        buildDrawingSession(session),
        buildDrawing(session.getId()),
        buildChildExpression(report, session),
        buildActivityFacts(report),
        buildConversationSummary(report),
        buildGuardianConversationGuide(report.getId()),
        splitLimitations(report.getLimitationsText()),
        ReportExpertReviewResponse.notRequested(),
        report.getCreatedAt());
  }

  private ReportDrawingSessionResponse buildDrawingSession(ReportDrawingSessionView session) {
    ReportDrawingTypeView drawingType =
        drawingTypeRepository.findById(session.getDrawingTypeId()).orElse(null);
    return new ReportDrawingSessionResponse(
        session.getId(),
        session.getChildId(),
        drawingType == null ? null : drawingType.getCode(),
        drawingType == null ? null : drawingType.getName(),
        session.getTitle(),
        session.getInputMethod(),
        session.getStartedAt(),
        session.getCompletedAt(),
        session.durationMs());
  }

  /**
   * 리포트 상세에 표시할 그림 URL을 확정한다.
   *
   * <p>사진 업로드로 진행한 세션은 최종 그림을 다시 그리지 않아 업로드 원본만 남으므로, {@code FINAL}이 없으면 {@code UPLOADED}를 최종 그림으로
   * 인정한다. 이 폴백이 없으면 업로드 세션 리포트의 그림 자리가 빈다. 목록·미리보기의 같은 규칙은 {@code SessionPreviewImageUrlFinder}가
   * 담당한다.
   *
   * @param drawingSessionId 리포트가 가리키는 그림 활동 세션 식별자
   * @return 최종 그림·미리보기 URL이며 그림 파일이 없으면 두 항목 모두 {@code null}
   */
  private ReportDrawingResponse buildDrawing(Long drawingSessionId) {
    List<ReportDrawingAssetView> assets =
        assetRepository.findByDrawingSessionIdAndAssetTypeInOrderByAssetVersionAsc(
            drawingSessionId, List.of(FINAL_ASSET_TYPE, THUMBNAIL_ASSET_TYPE, UPLOADED_ASSET_TYPE));
    Map<String, ReportDrawingAssetView> latestByType = new LinkedHashMap<>();
    for (ReportDrawingAssetView asset : assets) {
      ReportDrawingAssetView current = latestByType.get(asset.getAssetType());
      if (current == null || asset.getAssetVersion() >= current.getAssetVersion()) {
        latestByType.put(asset.getAssetType(), asset);
      }
    }
    String finalImageUrl = urlOf(latestByType.get(FINAL_ASSET_TYPE));
    if (finalImageUrl == null) {
      finalImageUrl = urlOf(latestByType.get(UPLOADED_ASSET_TYPE));
    }
    String thumbnailUrl = urlOf(latestByType.get(THUMBNAIL_ASSET_TYPE));
    return new ReportDrawingResponse(
        finalImageUrl, thumbnailUrl == null ? finalImageUrl : thumbnailUrl);
  }

  private String urlOf(ReportDrawingAssetView asset) {
    return asset == null ? null : fileUrlFactory.create(asset.getId());
  }

  private ReportChildExpressionResponse buildChildExpression(
      ReportDetailView report, ReportDrawingSessionView session) {
    List<String> selectedEmotions = new ArrayList<>();
    for (ReportDrawingEmotionView emotion :
        emotionRepository.findByDrawingSessionIdOrderBySelectionOrderAsc(session.getId())) {
      selectedEmotions.add(emotion.getEmotionCode());
    }

    List<ReportUtteranceResponse> utterances = new ArrayList<>();
    for (ReportKeyConversationView conversation :
        keyConversationRepository.findByReportIdOrderByDisplayOrderAsc(report.getId())) {
      utterances.add(
          new ReportUtteranceResponse(
              conversation.getAnswerMessageId(),
              conversation.getAnswerText(),
              deriveSource(conversation.getAnswerType()),
              false));
    }
    return new ReportChildExpressionResponse(
        selectedEmotions, session.getExpressedEmotionText(), utterances);
  }

  private String deriveSource(String answerType) {
    if (answerType != null && answerType.toUpperCase().contains("VOICE")) {
      return "STT";
    }
    return "TEXT";
  }

  private ReportActivityFactsResponse buildActivityFacts(ReportDetailView report) {
    ReportActivitySummaryView summary =
        activitySummaryRepository.findById(report.getId()).orElse(null);

    List<String> notes = new ArrayList<>();
    activityNoteRepository
        .findByReportIdOrderByDisplayOrderAsc(report.getId())
        .forEach(note -> notes.add(note.getNoteText()));

    return new ReportActivityFactsResponse(
        buildDetectedObjects(report),
        summary == null ? null : summary.getDrawingDurationMs(),
        summary == null ? null : summary.getPauseCount(),
        summary == null ? null : summary.getEraseCount(),
        summary != null && summary.isPressureAvailable(),
        notes);
  }

  /** 최신 리포트는 관찰 서술 항목을, 이전 리포트는 신뢰도 보정된 탐지 라벨만 사용한다. */
  private List<String> buildDetectedObjects(ReportDetailView report) {
    if (report.hasDrawnItems()) {
      return drawnItemRepository.findByReportIdOrderByDisplayOrderAsc(report.getId()).stream()
          .map(item -> item.getName())
          .filter(name -> name != null && !name.isBlank())
          .toList();
    }
    return buildLegacyDetectedObjects(report.getDrawingSessionId());
  }

  /**
   * 기존 리포트의 YOLO 라벨을 0.50 이상으로 제한해 반환한다.
   *
   * <p>조회 결과는 이미 주제 순서와 세션별 분석 최신순으로 정렬돼 있어, 세션마다 처음 만난 분석의 행만 남기면 세션당 최신 한 건이 된다. 탐지 결과가 없는 세션은 행이
   * 없어 자연히 건너뛴다.
   */
  private List<String> buildLegacyDetectedObjects(Long drawingSessionId) {
    List<String> detectedObjects = new ArrayList<>();
    Map<Long, Long> latestAnalysisBySession = new HashMap<>();
    for (ReportDetectedObjectRow row :
        detectedObjectRepository.findActivityDetectedObjects(drawingSessionId)) {
      Long latestAnalysisId =
          latestAnalysisBySession.computeIfAbsent(row.drawingSessionId(), key -> row.analysisId());
      if (!latestAnalysisId.equals(row.analysisId())) {
        continue;
      }
      String name = row.objectName();
      if (name != null
          && !name.isBlank()
          && row.confidenceScore() != null
          && row.confidenceScore().compareTo(LEGACY_DETECTION_MIN_CONFIDENCE) >= 0) {
        detectedObjects.add(name);
      }
    }
    return detectedObjects;
  }

  private ReportConversationSummaryResponse buildConversationSummary(ReportDetailView report) {
    ReportActivitySummaryView summary =
        activitySummaryRepository.findById(report.getId()).orElse(null);
    String summaryText = summary == null ? null : summary.getConversationSummary();
    if (summaryText == null || summaryText.isBlank()) {
      summaryText = fallbackSummaryText(report.getAnalysisId());
    }
    return new ReportConversationSummaryResponse(
        summary == null ? null : summary.getConversationQuestionCount(),
        summary == null ? null : summary.getConversationAnsweredCount(),
        summary == null ? null : summary.getConversationSkippedCount(),
        summaryText);
  }

  private String fallbackSummaryText(Long analysisId) {
    List<ReportConversationSummaryView> summaries =
        conversationSummaryRepository.findByAnalysisIdOrderByIdAsc(analysisId);
    for (ReportConversationSummaryView summary : summaries) {
      if (summary.getSummaryText() != null && !summary.getSummaryText().isBlank()) {
        return summary.getSummaryText();
      }
    }
    return null;
  }

  private List<String> buildGuardianConversationGuide(Long reportId) {
    List<String> guides = new ArrayList<>();
    followUpGuideRepository
        .findByReportIdOrderByDisplayOrderAsc(reportId)
        .forEach(guide -> guides.add(guide.getGuidance()));
    return guides;
  }

  private List<String> splitLimitations(String limitationsText) {
    List<String> limitations = new ArrayList<>();
    if (limitationsText == null) {
      return limitations;
    }
    for (String line : limitationsText.split("\\R")) {
      String trimmed = line.strip();
      if (!trimmed.isEmpty()) {
        limitations.add(trimmed);
      }
    }
    return limitations;
  }
}
