package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.document.StrokeBatchDocument;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

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
   * 행동 요약 집계에 필요한 필드만 담아 한 그림 활동의 Stroke 배치를 그린 순서대로 조회한다 (S15P11B209-772).
   *
   * <p><b>정렬은 {@code batchSeq} 다.</b> 수신 시각으로 정렬하면 안 된다. 전송 실패한 배치는 뒤늦게 재시도돼 들어오므로 저장·수신 순서가 실제로 그린
   * 순서와 어긋난다. 필터 키 {@code sessionId} 와 정렬 키 {@code batchSeq} 가 모두 {@code session_batch_unique}
   * ({@code {sessionId:1, batchSeq:1}}, {@code infra/k8s/base/mongodb-initdb.yaml}) 안에 있어 인덱스만으로
   * 필터와 정렬이 끝난다.
   *
   * <p><b>좌표 {@code x}·{@code y} 를 제외한다.</b> 집계가 좌표에서 읽는 값은 첫·마지막 점의 {@code t}(BSON 이름) 와 필압 {@code
   * p} 뿐이고 위치는 한 번도 보지 않는다. 그런데 좌표는 배치당 최대 20,000개이고 {@code x}·{@code y} 는 각각 {@link
   * java.math.BigDecimal} 객체라 점 하나가 차지하는 힙의 대부분이다. 읽지 않을 값을 힙에 올리지 않는다.
   *
   * <p><b>{@code Pageable} 로 개수를 제한한다.</b> 배치당 크기는 1 MiB 로 막혀 있지만(<code>StrokeBatchService</code>)
   * 세션당 배치 <b>수</b>에는 상한이 없다. 이 조회는 AI 호출 직전 동기 경로에서 일어나므로 결과 집합이 무제한이면 요청 스레드 힙과 read timeout 예산을
   * 함께 잠식한다. 호출부가 상한 + 1 을 요청해 절단 여부를 스스로 판별한다.
   *
   * @param sessionId 그림 활동 식별자
   * @param pageable 정렬과 개수 상한
   * @return 좌표 위치를 제외한 배치 목록
   */
  @Query(value = "{ 'sessionId': ?0 }", fields = "{ 'strokes.points.x': 0, 'strokes.points.y': 0 }")
  List<StrokeBatchDocument> findBehaviorAggregationInputs(Long sessionId, Pageable pageable);

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
