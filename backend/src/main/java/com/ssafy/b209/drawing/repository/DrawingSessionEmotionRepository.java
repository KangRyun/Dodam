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
   * 세션에 저장된 감정을 아동이 선택한 순서로 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 선택 순서와 식별자 순서가 적용된 감정 목록
   */
  List<DrawingSessionEmotion> findAllByDrawingSessionIdOrderBySelectionOrderAscIdAsc(
      Long drawingSessionId);

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
