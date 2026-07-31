package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 활동에 저장된 감정 선택 목록을 교체하는 Repository다. */
public interface DrawingSessionEmotionRepository
    extends JpaRepository<DrawingSessionEmotion, Long> {

  /**
   * 그림 활동에 선택 감정이 한 건 이상 저장되어 있는지 확인한다.
   *
   * @param drawingSessionId 확인할 그림 활동 세션 식별자
   * @return 선택 감정이 저장되어 있으면 {@code true}
   */
  boolean existsByDrawingSessionId(Long drawingSessionId);

  /**
   * 세션에 저장된 감정을 아동이 선택한 순서로 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 선택 순서와 식별자 순서가 적용된 감정 목록
   */
  List<DrawingSessionEmotion> findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
      Long drawingSessionId);

  /**
   * 여러 세션에 저장된 감정을 세션·선택 순서·식별자 순으로 한 번에 조회한다.
   *
   * <p>목록 조회에서 세션마다 개별 조회를 하지 않고 배치로 읽어 조립하기 위한 경계다.
   *
   * @param drawingSessionIds 그림 활동 세션 식별자 목록
   * @return 세션 식별자 오름차순, 선택 순서와 식별자 오름차순으로 정렬된 감정 목록
   */
  List<DrawingSessionEmotion>
      findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
          List<Long> drawingSessionIds);

  /**
   * 그림 활동에 기존 저장된 감정을 모두 제거한다.
   *
   * @param drawingSessionId 감정 목록을 교체할 그림 활동 세션 식별자
   */
  @Modifying
  @Query(
      "delete from DrawingSessionEmotion emotion "
          + "where emotion.drawingSession.id = :drawingSessionId")
  void deleteAllByDrawingSessionId(@Param("drawingSessionId") Long drawingSessionId);
}
