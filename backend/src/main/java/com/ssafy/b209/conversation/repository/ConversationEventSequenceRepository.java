package com.ssafy.b209.conversation.repository;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.FindAndModifyOptions;
import org.springframework.data.mongodb.core.MongoOperations;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.stereotype.Repository;

/**
 * 대화 행동 이벤트의 순번({@code seq})을 MongoDB 카운터로 발급한다 (S15P11B209-973).
 *
 * <p><b>왜 순번이 따로 필요한가</b>: initdb 가 만든 인덱스가 {@code {sessionId:1, seq:1}} 이라 정렬 키로 쓸 필드가 있어야 한다. 그런데
 * 발생 시각({@code occurredAt})은 정렬 키로 부족하다 — 같은 밀리초에 두 이벤트가 들어오면 순서가 실행마다 달라진다.
 *
 * <p><b>왜 세션별이 아니라 전역 카운터인가</b>: 세션마다 카운터 문서를 만들면 {@code counters} 컬렉션이 세션 수만큼 무한히 늘어난다. TTL 도 없어
 * 영원히 남는다. 전역 카운터는 문서 <b>하나</b>로 끝나고, 한 세션의 이벤트만 뽑아 정렬하면 어차피 발생 순서가 그대로 나온다 — 나중에 일어난 일이 항상 더 큰 번호를
 * 받기 때문이다. 스트로크 배치 ID 카운터({@code StrokeBatchIdSequenceRepository})와 같은 컬렉션·같은 방식을 쓴다.
 *
 * <p><b>왜 안전한가</b>: {@code findAndModify} + {@code $inc} 는 문서 하나에 대한 원자적 연산이다. 파드가 여러 개여도 같은 값이 두 번
 * 나오지 않는다.
 *
 * <p>번호가 <b>비는 것은 정상</b>이다. 다른 세션이 가져갔거나, 발급 후 적재가 실패하면 그 번호는 버려진다. 이벤트 적재는 best-effort 라 연속성을 보장하지
 * 않는다 — 소비자는 번호의 연속성으로 유실을 판정하면 안 된다.
 */
@Repository
public class ConversationEventSequenceRepository {

  /** 스트로크 배치 ID 와 같은 카운터 컬렉션. 문서가 {@code _id} 로 구분되므로 섞여도 충돌하지 않는다. */
  static final String COLLECTION = "counters";

  private static final String SEQUENCE_ID = "conversationEventSeq";

  private final MongoOperations mongoOperations;

  /**
   * 순번 발급에 사용할 MongoDB 접근 도구를 주입한다.
   *
   * @param mongoOperations 원자적 {@code findAndModify} 를 수행할 MongoDB Template
   */
  public ConversationEventSequenceRepository(MongoOperations mongoOperations) {
    this.mongoOperations = mongoOperations;
  }

  /**
   * 다음 이벤트 순번을 발급한다.
   *
   * @return 1부터 시작해 단조 증가하는 순번
   * @throws IllegalStateException 카운터 문서를 읽지 못한 경우
   */
  public long next() {
    ConversationEventSequenceCounter counter =
        mongoOperations.findAndModify(
            Query.query(Criteria.where("_id").is(SEQUENCE_ID)),
            new Update().inc("seq", 1L),
            FindAndModifyOptions.options().returnNew(true).upsert(true),
            ConversationEventSequenceCounter.class,
            COLLECTION);
    if (counter == null) {
      throw new IllegalStateException("Conversation event sequence is unavailable");
    }
    return counter.seq();
  }

  /**
   * 카운터 문서 한 건을 표현한다.
   *
   * @param id 카운터 이름
   * @param seq 마지막으로 발급한 값
   */
  record ConversationEventSequenceCounter(@Id String id, long seq) {}
}
