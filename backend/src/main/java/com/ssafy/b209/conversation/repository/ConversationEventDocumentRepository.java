package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.document.ConversationEventDocument;
import com.ssafy.b209.conversation.document.ConversationEventType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.mongodb.repository.MongoRepository;

/**
 * 대화 행동 이벤트를 MongoDB {@code conversation_events} 컬렉션에 적재하고 조회한다 (S15P11B209-973).
 *
 * <p><b>멱등 제약이 없다.</b> 스트로크의 {@code session_batch_unique} 같은 unique 인덱스가 여기에는 없다(initdb 의 {@code
 * session_seq} 는 unique 가 아니다). 이벤트는 커밋 이후 한 번만 기록하는 관측 로그이고, 중복이 생기더라도 대화를 막지 않는 편이 낫기 때문이다. 소비자가
 * 중복에 민감하다면 {@code questionMessageId} + {@code eventType} 으로 중복을 접어서 쓸 것.
 */
public interface ConversationEventDocumentRepository
    extends MongoRepository<ConversationEventDocument, String> {

  /**
   * 한 질문의 제시 이벤트를 찾는다. 응답 지연과 질문 순번의 기준점이다.
   *
   * <p>필터 선두 키 {@code sessionId} 가 {@code session_seq} 인덱스({@code {sessionId:1, seq:1}}) 안에 있어 한
   * 대화의 이벤트만 훑는다. 한 대화의 이벤트는 질문 상한(수 개~수십 개) 규모라 나머지 조건을 메모리에서 걸러도 비용이 없다.
   *
   * <p>같은 질문에 제시 이벤트가 둘 이상이면(재시도 등) 가장 이른 것을 쓴다 — 아이가 질문을 처음 본 시각이 응답 지연의 기준이다.
   *
   * @param sessionId 대화 세션 식별자
   * @param questionMessageId 질문 메시지 식별자
   * @param eventType 찾을 이벤트 종류
   * @return 가장 이른 이벤트 또는 빈 값
   */
  Optional<ConversationEventDocument>
      findFirstBySessionIdAndQuestionMessageIdAndEventTypeOrderBySeqAsc(
          Long sessionId, Long questionMessageId, ConversationEventType eventType);

  /**
   * 한 대화의 모든 행동 이벤트를 일어난 순서대로 조회한다.
   *
   * <p><b>정렬은 {@code seq} 다.</b> {@code occurredAt} 으로 정렬하면 같은 밀리초에 일어난 두 이벤트의 순서가 실행마다 달라진다.
   *
   * @param sessionId 대화 세션 식별자
   * @return 발생 순서의 이벤트 목록
   */
  List<ConversationEventDocument> findBySessionIdOrderBySeqAsc(Long sessionId);

  /**
   * 한 아동의 모든 대화 행동 이벤트를 삭제한다.
   *
   * <p>아동 프로필 삭제·회원 탈퇴 경로에서 쓴다. TTL 은 "언젠가 지운다"이지 즉시가 아니므로(최대 60초 + 부하에 따라 더) 동의 철회 성격의 삭제는 기다리지 않고
   * 지운다 (CLAUDE.md 9절 · 저장소-아키텍처 §5). initdb 의 {@code child_lookup} 인덱스가 이 삭제를 위해 존재한다.
   *
   * @param childId 삭제 대상 아동 식별자
   * @return 삭제한 문서 수
   */
  long deleteByChildId(Long childId);

  /**
   * 한 아동의 특정 그림 활동에 딸린 대화 행동 이벤트를 삭제한다.
   *
   * <p><b>{@code childId} 를 함께 받는 이유는 인덱스다.</b> {@code drawingSessionId} 에는 인덱스가 없어 단독 조건이면 컬렉션 전체를
   * 훑는다. 선두에 {@code childId} 를 두면 {@code child_lookup} 으로 그 아동의 문서만 좁힌 뒤 활동을 가려낸다. 인덱스는 앱이 아니라
   * initdb 가 관리하므로(문서 주석 참고) 여기서 새 인덱스를 만들지 않고 있는 것을 쓴다.
   *
   * @param childId 활동을 소유한 아동 식별자
   * @param drawingSessionId 삭제 대상 그림 활동 식별자
   * @return 삭제한 문서 수
   */
  long deleteByChildIdAndDrawingSessionId(Long childId, Long drawingSessionId);
}
