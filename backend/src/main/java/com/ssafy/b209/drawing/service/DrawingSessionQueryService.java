package com.ssafy.b209.drawing.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.response.ActiveDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionAnalysisSummaryResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionAssetSummaryResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionChildSummaryResponse;
import com.ssafy.b209.drawing.dto.response.DrawingSessionDetailResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeSummaryResponse;
import com.ssafy.b209.drawing.dto.response.LatestDrawingDraftResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자가 접근할 수 있는 그림 활동의 현재 상태와 재개에 필요한 Metadata 조회를 담당한다.
 *
 * <p>세션 생성·자동 저장 트랜잭션과 분리된 읽기 전용 경계이며 세션 상태나 초안 파일을 변경하지 않는다. 한 아동에게 활성 세션이 둘 이상 존재하면 임의로 선택하지 않고
 * 데이터 무결성 오류로 처리한다.
 */
@Service
@Transactional(readOnly = true)
public class DrawingSessionQueryService {

  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingAssetRepository drawingAssetRepository;
  private final DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  private final DrawingAnalysisRepository drawingAnalysisRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final ReportRepository reportRepository;
  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;

  /**
   * 그림 활동 상태와 연관 리소스 Metadata 조회에 사용할 저장소를 구성한다.
   *
   * @param drawingSessionRepository 세션 조회 저장소
   * @param drawingAssetRepository 그림 파일 Metadata 조회 저장소
   * @param drawingSessionEmotionRepository 선택 감정 조회 저장소
   * @param drawingAnalysisRepository 분석 실행 조회 저장소
   * @param conversationSessionRepository 대화 세션 조회 저장소
   * @param reportRepository 리포트 조회 저장소
   * @param currentUserResolver Access Token에서 현재 사용자 ID를 제공하는 Resolver
   * @param accessValidator 보호자와 그림 활동의 연결 관계를 검증하는 Validator
   */
  public DrawingSessionQueryService(
      DrawingSessionRepository drawingSessionRepository,
      DrawingAssetRepository drawingAssetRepository,
      DrawingSessionEmotionRepository drawingSessionEmotionRepository,
      DrawingAnalysisRepository drawingAnalysisRepository,
      ConversationSessionRepository conversationSessionRepository,
      ReportRepository reportRepository,
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingAssetRepository = drawingAssetRepository;
    this.drawingSessionEmotionRepository = drawingSessionEmotionRepository;
    this.drawingAnalysisRepository = drawingAnalysisRepository;
    this.conversationSessionRepository = conversationSessionRepository;
    this.reportRepository = reportRepository;
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
  }

  /**
   * 보호자가 접근할 수 있는 그림 활동과 최신 연관 리소스 Metadata를 조회한다.
   *
   * <p>연관 리소스가 없어도 세션 조회는 성공하며 조회 과정에서 상태 변경이나 외부 시스템 호출을 수행하지 않는다.
   *
   * @param drawingSessionId 조회할 그림 활동 세션 식별자
   * @return 세션 상태와 최신 그림·분석·대화·리포트 요약
   * @throws BusinessException 접근할 수 없거나 삭제된 세션인 경우
   */
  public DrawingSessionDetailResponse getDrawingSessionDetail(Long drawingSessionId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    DrawingSession session =
        drawingSessionRepository
            .findDetailById(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));

    List<DrawingEmotionCode> emotions =
        drawingSessionEmotionRepository
            .findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(drawingSessionId)
            .stream()
            .map(DrawingSessionEmotion::getEmotionCode)
            .toList();

    return new DrawingSessionDetailResponse(
        session.getId(),
        new DrawingSessionChildSummaryResponse(
            session.getChild().getId(), session.getChild().getNickname()),
        toDrawingTypeSummary(session.getDrawingType()),
        session.getInputMethod(),
        session.getTitle(),
        emotions,
        session.getSessionStatus(),
        session.getCurrentStage(),
        drawingAssetRepository
            .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(drawingSessionId)
            .map(this::toAssetSummary)
            .orElse(null),
        drawingAnalysisRepository
            .findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(drawingSessionId)
            .map(this::toAnalysisSummary)
            .orElse(null),
        conversationSessionRepository
            .findByDrawingSessionId(drawingSessionId)
            .map(ConversationSession::getId)
            .orElse(null),
        reportRepository
            .findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(drawingSessionId)
            .map(Report::getId)
            .orElse(null),
        session.getStartedAt().toInstant(ZoneOffset.UTC),
        toNullableInstant(session.getCompletedAt()),
        drawingAssetRepository.existsByDrawingSessionIdAndAssetType(
            drawingSessionId, DrawingAssetType.DRAFT));
  }

  /**
   * 아동의 단일 진행 중 그림 활동 세션과 가장 높은 버전의 자동 저장 초안을 조회한다.
   *
   * <p>저장된 초안이 없더라도 세션 조회는 성공하며 응답의 {@code latestDraft}가 {@code null}이 된다.
   *
   * @param childId 진행 중인 그림 활동을 조회할 아동 식별자
   * @return 세션 요약과 공개 가능한 최신 초안 Metadata
   * @throws BusinessException 진행 중 세션이 없거나 둘 이상 존재하는 경우
   */
  public ActiveDrawingSessionResponse getActiveDrawingSession(Long childId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireChildAccess(guardianUserId, childId);
    List<DrawingSession> sessions = drawingSessionRepository.findActiveSessionsByChildId(childId);
    if (sessions.isEmpty()) {
      throw new BusinessException(DrawingErrorCode.ACTIVE_DRAWING_SESSION_NOT_FOUND);
    }
    if (sessions.size() > 1) {
      throw new BusinessException(DrawingErrorCode.MULTIPLE_ACTIVE_DRAWING_SESSIONS);
    }

    DrawingSession session = sessions.getFirst();
    LatestDrawingDraftResponse latestDraft =
        drawingAssetRepository
            .findLatestDraft(session.getId())
            .map(this::toLatestDraftResponse)
            .orElse(null);
    return new ActiveDrawingSessionResponse(
        session.getId(),
        session.getChild().getId(),
        toDrawingTypeSummary(session.getDrawingType()),
        session.getInputMethod(),
        session.getSessionStatus(),
        session.getCurrentStage(),
        session.getStartedAt().toInstant(ZoneOffset.UTC),
        latestDraft);
  }

  /**
   * 보호자가 접근할 수 있는 그림 활동의 그림 파일 스냅샷 목록을 최신순으로 조회한다.
   *
   * <p>내부 저장 위치는 응답에 포함하지 않으며 조회 과정에서 상태를 변경하지 않는다.
   *
   * @param drawingSessionId 조회할 그림 활동 세션 식별자
   * @return 최신순 그림 파일 Metadata 목록, 없으면 빈 목록
   * @throws BusinessException 접근할 수 없거나 삭제된 세션인 경우
   */
  public List<DrawingSessionAssetSummaryResponse> getSnapshots(Long drawingSessionId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    return drawingAssetRepository
        .findAllByDrawingSessionIdOrderByCreatedAtDescIdDesc(drawingSessionId)
        .stream()
        .map(this::toAssetSummary)
        .toList();
  }

  private LatestDrawingDraftResponse toLatestDraftResponse(DrawingAsset draft) {
    return new LatestDrawingDraftResponse(
        draft.getId(),
        draft.getAssetVersion(),
        draft.getLastEventSequence(),
        draft.getMimeType(),
        draft.getFileSizeBytes(),
        draft.getCapturedAt().toInstant(ZoneOffset.UTC),
        draft.getCreatedAt().toInstant(ZoneOffset.UTC),
        null);
  }

  private DrawingTypeSummaryResponse toDrawingTypeSummary(DrawingType type) {
    return new DrawingTypeSummaryResponse(type.getId(), type.getCode(), type.getName());
  }

  private DrawingSessionAssetSummaryResponse toAssetSummary(DrawingAsset asset) {
    return new DrawingSessionAssetSummaryResponse(
        asset.getId(),
        asset.getAssetType(),
        asset.getAssetVersion(),
        asset.getMimeType(),
        asset.getFileSizeBytes(),
        asset.getWidthPx(),
        asset.getHeightPx(),
        asset.getCapturedAt().toInstant(ZoneOffset.UTC),
        asset.getCreatedAt().toInstant(ZoneOffset.UTC));
  }

  private DrawingSessionAnalysisSummaryResponse toAnalysisSummary(DrawingAnalysis analysis) {
    return new DrawingSessionAnalysisSummaryResponse(
        analysis.getId(),
        analysis.getScope(),
        analysis.getTaskType(),
        analysis.getState(),
        analysis.getRequestedAt().toInstant(ZoneOffset.UTC),
        toNullableInstant(analysis.getCompletedAt()));
  }

  private Instant toNullableInstant(LocalDateTime dateTime) {
    return dateTime == null ? null : dateTime.toInstant(ZoneOffset.UTC);
  }
}
