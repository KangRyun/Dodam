package com.ssafy.b209.drawing.service;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.SaveDrawingReflectionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingReflectionResponse;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.HashSet;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 연결 보호자가 그림 활동의 제목과 아동이 직접 표현한 감정을 저장하는 Use Case를 수행한다.
 *
 * <p>기존 감정 목록은 PUT 요청 단위로 교체하며, 세션 잠금 안에서 제목·감정과 REFLECTION 단계 전이를 함께 반영한다.
 */
@Service
public class DrawingReflectionService {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianResourceAccessValidator accessValidator;
  private final DrawingSessionRepository drawingSessionRepository;
  private final DrawingSessionEmotionRepository emotionRepository;

  /**
   * 그림 활동 감정 저장에 필요한 인증·권한·영속성 의존성을 구성한다.
   *
   * @param currentUserResolver Access Token에서 현재 사용자 ID를 제공하는 Resolver
   * @param accessValidator 보호자와 그림 활동의 연결 관계를 검증하는 Validator
   * @param drawingSessionRepository 세션 잠금과 상태 변경을 담당하는 Repository
   * @param emotionRepository 정규화된 감정 선택 목록 Repository
   */
  public DrawingReflectionService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      GuardianResourceAccessValidator accessValidator,
      DrawingSessionRepository drawingSessionRepository,
      DrawingSessionEmotionRepository emotionRepository) {
    this.currentUserResolver = currentUserResolver;
    this.accessValidator = accessValidator;
    this.drawingSessionRepository = drawingSessionRepository;
    this.emotionRepository = emotionRepository;
  }

  /**
   * 그림 활동의 제목과 감정 표현을 현재 요청 값으로 교체한다.
   *
   * @param drawingSessionId 저장 대상 그림 활동 세션 식별자
   * @param request 제목, 선택 감정, 직접 표현과 건너뛰기 여부
   * @return REFLECTION 단계로 전이된 저장 결과
   * @throws BusinessException 요청 조합, 소유 관계 또는 세션 상태가 유효하지 않은 경우
   */
  @Transactional
  public DrawingReflectionResponse save(
      Long drawingSessionId, SaveDrawingReflectionRequest request) {
    validate(request);
    Long guardianUserId = currentUserResolver.requireUserId();
    accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
    DrawingSession drawingSession =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(drawingSessionId)
            .orElseThrow(() -> new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
    if (!drawingSession.canSaveReflection()) {
      throw new BusinessException(DrawingErrorCode.DRAWING_REFLECTION_NOT_ALLOWED);
    }

    List<DrawingSessionEmotion> emotions =
        request.selectedEmotions().stream()
            .map(
                emotion ->
                    DrawingSessionEmotion.create(
                        drawingSession, emotion, request.selectedEmotions().indexOf(emotion)))
            .toList();
    emotionRepository.deleteAllByDrawingSessionId(drawingSessionId);
    emotionRepository.saveAll(emotions);
    drawingSession.saveReflection(
        normalize(request.title()), normalize(request.expressedEmotionText()));

    return new DrawingReflectionResponse(
        drawingSessionId, DrawingStage.REFLECTION, request.selectedEmotions(), request.skipped());
  }

  private void validate(SaveDrawingReflectionRequest request) {
    if (request == null || request.selectedEmotions() == null) {
      throw new BusinessException(DrawingErrorCode.DRAWING_REFLECTION_INVALID);
    }
    List<DrawingEmotionCode> emotions = request.selectedEmotions();
    boolean duplicated = new HashSet<>(emotions).size() != emotions.size();
    boolean unknownCombined = emotions.contains(DrawingEmotionCode.UNKNOWN) && emotions.size() > 1;
    boolean invalidSkipped =
        request.skipped()
            && (!emotions.isEmpty() || normalize(request.expressedEmotionText()) != null);
    boolean missingSelection = !request.skipped() && emotions.isEmpty();
    if (duplicated || unknownCombined || invalidSkipped || missingSelection) {
      throw new BusinessException(DrawingErrorCode.DRAWING_REFLECTION_INVALID);
    }
  }

  private String normalize(String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    return value.trim();
  }
}
