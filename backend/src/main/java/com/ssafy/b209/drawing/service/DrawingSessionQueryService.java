package com.ssafy.b209.drawing.service;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.dto.response.ActiveDrawingSessionResponse;
import com.ssafy.b209.drawing.dto.response.DrawingTypeSummaryResponse;
import com.ssafy.b209.drawing.dto.response.LatestDrawingDraftResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 아동의 진행 중 그림 활동 세션과 재개에 필요한 최신 초안 Metadata 조회를 담당한다.
 *
 * <p>세션 생성·자동 저장 트랜잭션과 분리된 읽기 전용 경계이며 세션 상태나 초안 파일을 변경하지 않는다. 한 아동에게 활성 세션이 둘 이상 존재하면 임의로 선택하지 않고
 * 데이터 무결성 오류로 처리한다.
 */
@Service
@Transactional(readOnly = true)
public class DrawingSessionQueryService {

  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingAssetRepository drawingAssetRepository;

  /**
   * 진행 중 세션과 최신 초안 Metadata 조회에 사용할 저장소를 구성한다.
   *
   * @param drawingSessionRepository 진행 중 세션 조회 저장소
   * @param drawingAssetRepository 최신 초안 Metadata 조회 저장소
   */
  public DrawingSessionQueryService(
      DrawingSessionRepository drawingSessionRepository,
      DrawingAssetRepository drawingAssetRepository) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingAssetRepository = drawingAssetRepository;
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
    DrawingType type = session.getDrawingType();
    return new ActiveDrawingSessionResponse(
        session.getId(),
        session.getChild().getId(),
        new DrawingTypeSummaryResponse(type.getId(), type.getCode(), type.getName()),
        session.getInputMethod(),
        session.getSessionStatus(),
        session.getCurrentStage(),
        session.getStartedAt().toInstant(ZoneOffset.UTC),
        latestDraft);
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
}
