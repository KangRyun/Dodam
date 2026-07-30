package com.ssafy.b209.drawing.document;

import java.time.Instant;
import java.util.List;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * 한 그림 활동에서 연속 수신한 캔버스 이벤트와 행동 지표를 MongoDB 문서 하나로 보존한다 (S15P11B209-365).
 *
 * <p><b>왜 MongoDB 인가</b>: MySQL 에서는 좌표 1개가 {@code stroke_event_points} 1행이라 세션당 수만~10만 행이 쌓였다. 그런데
 * 이 데이터는 조인 없이 "세션 단위로 통째 재생"만 한다. 배치 1건 = 문서 1개로 묶으면 행마다 붙던 인덱스 갱신·redo 비용이 사라진다.
 *
 * <p><b>⚠️ 필드 이름을 바꾸지 말 것.</b> {@code sessionId}·{@code batchSeq}·{@code childId}·{@code expireAt}
 * 은 initdb(364/634)가 만든 인덱스의 키다. 이름이 어긋나면 인덱스를 타지 않고, 특히 {@code expireAt} 이 어긋나면 <b>TTL 이 조용히 동작하지
 * 않는다</b> — 보관 기간이 지난 아동 데이터가 남는다는 뜻이다(가드레일 9절).
 *
 * <p><b>⚠️ 시각은 전부 {@link Instant} 다.</b> {@code LocalDateTime} 을 쓰면 파드(UTC)와 MySQL 저장 규약(KST) 사이에서
 * 9시간 어긋난다. Mongo 는 BSON Date(UTC epoch)로 저장하므로 시간대 개념이 아예 없는 {@code Instant} 가 유일하게 안전한 타입이다.
 *
 * <p><b>인덱스는 앱이 만들지 않는다.</b> {@code auto-index-creation: false} + 무어노테이션. 보관 정책이 코드와 인프라 두 곳으로 흩어지지
 * 않게 인덱스는 initdb 와 634 의 관리 절차에서만 다룬다.
 *
 * @param id 배치 식별자이며 API 응답의 {@code batchId} 다. 앱이 숫자로 파싱하므로 반드시 정수여야 한다
 * @param sessionId 그림 활동 세션 ID
 * @param childId 아동 ID. 탈퇴·아동 삭제 시 즉시 동반 삭제하는 키다
 * @param batchSeq 세션 내 배치 순번. {@code sessionId} 와 묶여 멱등 키를 이룬다
 * @param firstEventSeq 첫 이벤트 순번
 * @param lastEventSeq 마지막 이벤트 순번
 * @param eventCount 저장된 이벤트 수
 * @param pointCount 저장된 좌표 총수
 * @param payloadChecksumSha256 요청 payload 의 SHA-256. 같은 순번 재전송이 같은 내용인지 판별한다
 * @param undoCountDelta 실행 취소 증가량
 * @param redoCountDelta 다시 실행 증가량
 * @param eraseCountDelta 지우기 증가량
 * @param pauseDurationMsDelta 일시 정지 시간 증가량(ms)
 * @param clientCreatedAt 클라이언트가 배치를 만든 시각
 * @param receivedAt 서버가 배치를 수신한 시각
 * @param createdAt 문서 생성 시각
 * @param expireAt TTL 만료 시각. {@code createdAt + app.stroke.retention-days}
 * @param strokes 순서화된 이벤트 목록
 */
@Document(collection = "strokes")
public record StrokeBatchDocument(
    @Id Long id,
    Long sessionId,
    Long childId,
    int batchSeq,
    long firstEventSeq,
    long lastEventSeq,
    int eventCount,
    int pointCount,
    String payloadChecksumSha256,
    int undoCountDelta,
    int redoCountDelta,
    int eraseCountDelta,
    long pauseDurationMsDelta,
    Instant clientCreatedAt,
    Instant receivedAt,
    Instant createdAt,
    Instant expireAt,
    List<StrokeEventDocument> strokes) {}
