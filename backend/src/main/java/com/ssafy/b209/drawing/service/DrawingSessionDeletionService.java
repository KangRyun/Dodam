package com.ssafy.b209.drawing.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.dto.request.DeleteDrawingSessionRequest;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionDeletionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결 보호자가 그림 활동을 취소하거나 기록을 삭제하는 Use Case다.
 *
 * <p>세션은 Soft Delete하고 그림·대화 음성·리포트 파일은 Transaction 안에서 비동기 삭제 작업으로 등록한다. 실제 Storage 삭제는 이 요청에서
 * 수행하지 않는다.
 */
@Service
public class DrawingSessionDeletionService {

  private static final String CONFIRMATION = "DELETE";

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingSessionDeletionRepository deletionRepository;
  private final Clock clock;

  /**
   * 그림 활동 삭제에 필요한 인증, 잠금과 파일 삭제 예약 의존성을 구성한다.
   *
   * @param currentUserResolver 현재 인증 사용자 ID Resolver
   * @param accessValidator 보호자와 그림 활동 연결 관계 Validator
   * @param drawingSessionRepository 세션 잠금과 상태 저장 Repository
   * @param deletionRepository Storage 삭제 작업 등록 Repository
   * @param clock 서버 삭제 시각을 제공하는 UTC Clock
   */
  public DrawingSessionDeletionService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      DrawingSessionRepository drawingSessionRepository,
      DrawingSessionDeletionRepository deletionRepository,
      Clock clock) {
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.drawingSessionRepository = drawingSessionRepository;
    this.deletionRepository = deletionRepository;
    this.clock = clock;
  }

  /**
   * 확인 문자열과 보호자 접근 권한을 검증한 뒤 그림 활동을 Soft Delete한다.
   *
   * @param drawingSessionId 삭제할 그림 활동 세션 ID
   * @param request 명시적 삭제 확인 요청
   * @throws BusinessException 확인 문자열이 다르거나 접근 가능한 세션이 없는 경우
   */
  @Transactional
  public void delete(Long drawingSessionId, DeleteDrawingSessionRequest request) {
    if (!CONFIRMATION.equals(request.confirmation())) {
      throw new BusinessException(DrawingErrorCode.DRAWING_DELETION_CONFIRMATION_MISMATCH);
    }
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    DrawingSession session =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));

    session.softDelete(LocalDateTime.now(clock));
    deletionRepository.scheduleStorageDeletions(drawingSessionId);
  }
}
