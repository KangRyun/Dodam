package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.StrokeBatch;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 세션별 Stroke 배치 순번을 멱등 키로 저장하고 조회한다. */
public interface StrokeBatchRepository extends JpaRepository<StrokeBatch, Long> {

  /**
   * 세션과 배치 순번으로 기존 저장 결과를 조회한다.
   *
   * @param drawingSessionId 그림 활동 식별자
   * @param batchSequence 세션 내 배치 순번
   * @return 저장된 배치 또는 빈 값
   */
  Optional<StrokeBatch> findByDrawingSession_IdAndBatchSequence(
      Long drawingSessionId, int batchSequence);
}
