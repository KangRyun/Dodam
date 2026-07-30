package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.document.StrokeBatchDocument;
import java.util.Optional;
import org.springframework.data.mongodb.repository.MongoRepository;

/**
 * 세션별 Stroke 배치를 MongoDB {@code strokes} 컬렉션에 저장하고 조회한다 (S15P11B209-365).
 *
 * <p>멱등 키는 {@code (sessionId, batchSeq)} 이며 unique 인덱스 {@code session_batch_unique} 가 강제한다. 앱의
 * 선조회만으로는 동시 요청을 막지 못하므로(조회와 저장 사이에 다른 요청이 끼어든다) 중복 차단의 최종 근거는 이 인덱스다.
 */
public interface StrokeBatchDocumentRepository extends MongoRepository<StrokeBatchDocument, Long> {

  /**
   * 세션과 배치 순번으로 기존 저장 결과를 조회한다.
   *
   * @param sessionId 그림 활동 식별자
   * @param batchSeq 세션 내 배치 순번
   * @return 저장된 배치 또는 빈 값
   */
  Optional<StrokeBatchDocument> findBySessionIdAndBatchSeq(Long sessionId, int batchSeq);

  /**
   * 한 그림 활동의 모든 Stroke 배치를 삭제한다.
   *
   * <p>보관 기간(TTL)을 기다리지 않는 즉시 삭제다. 세션이 삭제되면 그리기 과정 데이터도 함께 사라져야 한다.
   *
   * @param sessionId 삭제 대상 그림 활동 식별자
   * @return 삭제한 문서 수
   */
  long deleteBySessionId(Long sessionId);

  /**
   * 한 아동의 모든 Stroke 배치를 삭제한다.
   *
   * <p>아동 프로필 삭제·회원 탈퇴 경로에서 쓴다. TTL 은 "언젠가 지운다"이지 즉시가 아니므로(최대 60초 + 부하에 따라 더) 동의 철회 성격의 삭제는 기다리지 않고
   * 지운다 (CLAUDE.md 9절 · 저장소-아키텍처 §5).
   *
   * @param childId 삭제 대상 아동 식별자
   * @return 삭제한 문서 수
   */
  long deleteByChildId(Long childId);
}
