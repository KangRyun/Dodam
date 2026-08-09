package com.ssafy.b209.infrastructure.ai.drawing;

import com.ssafy.b209.drawing.service.StrokeBehaviorSummary;
import java.util.Optional;

/**
 * 그림 활동의 저장된 그리기 과정 요약을 AI 어댑터에 공급하는 경계다 (S15P11B209-772).
 *
 * <p>어댑터가 Stroke 저장소를 직접 알지 않게 한 곳으로 좁힌다. 캔버스 과정이 없는 활동에서는 빈 값을 돌려주며, 구현체가 0으로 채운 요약을 대신 만들어서는 안
 * 된다.
 */
@FunctionalInterface
public interface DrawingBehaviorSummaryProvider {

  /**
   * 그림 활동에 저장된 행동 요약을 조회한다.
   *
   * @param drawingSessionId 그림 활동 식별자
   * @return 집계된 행동 요약, 저장된 Stroke 배치가 없으면 빈 값
   */
  Optional<StrokeBehaviorSummary> findByDrawingSession(Long drawingSessionId);
}
