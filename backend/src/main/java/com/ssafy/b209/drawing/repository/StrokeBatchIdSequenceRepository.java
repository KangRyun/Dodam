package com.ssafy.b209.drawing.repository;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.FindAndModifyOptions;
import org.springframework.data.mongodb.core.MongoOperations;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.stereotype.Repository;

/**
 * Stroke 배치 문서에 부여할 <b>숫자</b> 식별자를 MongoDB 카운터로 발급한다 (S15P11B209-365).
 *
 * <p><b>왜 ObjectId 를 쓰지 않는가</b>: {@code batchId} 는 이미 배포된 API 계약이다. Flutter 앱이 {@code
 * json['batchId'] as int} 로 파싱하므로 문자열(ObjectId)을 내려보내면 앱이 파싱 단계에서 죽는다 — 그리기 과정 데이터가 통째로 유실된다. 저장소를
 * 바꾸는 작업이 클라이언트 계약을 깨서는 안 되므로, MySQL AUTO_INCREMENT 가 주던 "단조 증가 정수"를 Mongo 쪽에서 그대로 재현한다.
 *
 * <p><b>왜 안전한가</b>: {@code findAndModify} + {@code $inc} 는 문서 하나에 대한 원자적 연산이다. 파드가 여러 개여도 같은 값이 두 번
 * 나오지 않는다. 애플리케이션에서 "최댓값 조회 후 +1" 하는 방식과 근본적으로 다른 지점이다.
 *
 * <p>번호가 <b>비는 것은 정상</b>이다. 발급 후 삽입이 실패하면(동시 요청 경합) 그 번호는 버려진다. 연속성을 보장할 필요가 없는 식별자이므로 되돌리지 않는다.
 */
@Repository
public class StrokeBatchIdSequenceRepository {

  /**
   * 카운터 컬렉션. initdb 가 만들지 않으므로 첫 발급 때 MongoDB 가 암묵 생성한다(앱 계정의 {@code readWrite} 권한으로 가능). 인덱스는 필요
   * 없다 — {@code _id} 조회 하나뿐이다.
   */
  static final String COLLECTION = "counters";

  private static final String SEQUENCE_ID = "strokeBatchId";

  private final MongoOperations mongoOperations;

  /**
   * 카운터 발급에 사용할 MongoDB 접근 도구를 주입한다.
   *
   * @param mongoOperations 원자적 {@code findAndModify} 를 수행할 MongoDB Template
   */
  public StrokeBatchIdSequenceRepository(MongoOperations mongoOperations) {
    this.mongoOperations = mongoOperations;
  }

  /**
   * 다음 배치 식별자를 발급한다.
   *
   * @return 1부터 시작해 단조 증가하는 식별자
   * @throws IllegalStateException 카운터 문서를 읽지 못한 경우
   */
  public long next() {
    StrokeBatchIdCounter counter =
        mongoOperations.findAndModify(
            Query.query(Criteria.where("_id").is(SEQUENCE_ID)),
            new Update().inc("seq", 1L),
            FindAndModifyOptions.options().returnNew(true).upsert(true),
            StrokeBatchIdCounter.class,
            COLLECTION);
    if (counter == null) {
      throw new IllegalStateException("Stroke batch id sequence is unavailable");
    }
    return counter.seq();
  }

  /**
   * 카운터 문서 한 건을 표현한다.
   *
   * @param id 카운터 이름
   * @param seq 마지막으로 발급한 값
   */
  record StrokeBatchIdCounter(@Id String id, long seq) {}
}
