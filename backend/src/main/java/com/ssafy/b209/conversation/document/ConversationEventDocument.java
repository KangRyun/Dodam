package com.ssafy.b209.conversation.document;

import java.time.Instant;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * 대화 한 턴에서 일어난 <b>행동</b> 하나를 MongoDB 문서 하나로 남긴다 (S15P11B209-973).
 *
 * <p><b>⚠️ 여기에는 아이가 "무슨 말을 했는지"가 절대 들어가지 않는다.</b> 음성 전사(STT)·직접 입력 텍스트·선택한 칩의 라벨은 전부 제외한다. 이 문서가
 * 답하는 질문은 "무엇을 했는가"다 — 얼마나 걸려 답했는가, 말로 답했나 칩으로 답했나, 몇 개를 골랐나, 건너뛰었나. 발화 내용의 단일 소스는 MySQL {@code
 * conversation_messages} 이고 그대로 둔다(저장소-아키텍처 §5 "확정 전 이중 저장 금지"). 필드를 추가할 때 이 경계를 다시 확인할 것 — {@code
 * selectedOptionLabel} 같은 필드 하나가 이 컬렉션을 아동 발화 사본으로 만든다 (CLAUDE.md 9절).
 *
 * <p><b>⚠️ 필드 이름을 바꾸지 말 것.</b> {@code sessionId}·{@code seq}·{@code childId}·{@code expireAt} 은
 * initdb({@code infra/k8s/base/mongodb-initdb.yaml})가 만든 인덱스의 키다. 이름이 어긋나면 인덱스를 타지 않고, 특히 {@code
 * expireAt} 이 어긋나면 <b>TTL 이 조용히 동작하지 않는다</b> — 보관 기간이 지난 아동 데이터가 남는다는 뜻이다.
 *
 * <p><b>시각은 전부 {@link Instant} 다.</b> {@code LocalDateTime} 을 쓰면 파드(UTC)와 MySQL 저장 규약(KST) 사이에서 9시간
 * 어긋난다. 스트로크 문서와 같은 규칙이다(S15P11B209-365).
 *
 * <p><b>인덱스는 앱이 만들지 않는다.</b> {@code auto-index-creation: false} + 무어노테이션. 보관 정책이 코드와 인프라 두 곳으로 흩어지지
 * 않게 인덱스는 initdb 의 관리 절차에서만 다룬다.
 *
 * @param id MongoDB 가 발급하는 ObjectId. 스트로크와 달리 숫자여야 할 이유가 없다 — 이 식별자는 어떤 API 계약에도 실리지 않는다
 * @param sessionId 대화 세션 ID({@code conversation_sessions.id}). 인덱스 {@code session_seq} 의 선두 키다
 * @param seq 이벤트 순번. <b>세션 내가 아니라 전역으로 단조 증가한다</b> — 한 세션의 이벤트만 뽑아 {@code seq} 오름차순으로 정렬하면 실제 발생
 *     순서가 된다. 번호가 비는 것은 정상이다(다른 세션이 가져갔거나 적재가 실패했다)
 * @param childId 아동 ID({@code children.id}). 스트로크와 <b>같은 식별 체계</b>이며, 탈퇴·아동 삭제 시 즉시 동반 삭제하는 키다
 * @param drawingSessionId 그림 활동 세션 ID({@code drawing_sessions.id}). {@code strokes} 컬렉션의 {@code
 *     sessionId} 와 같은 값이라 그리기 과정 데이터와 대조할 때 쓴다
 * @param eventType 행동의 종류
 * @param questionMessageId 이 행동이 겨냥한 AI 질문 메시지 ID. {@code SESSION_END} 는 {@code null}
 * @param questionSeq 그 질문의 대화 내 순번(= 질문 메시지의 {@code message_sequence}). {@code QUESTION_SHOWN} 의 선행
 *     이벤트를 찾지 못했거나 {@code SESSION_END} 면 {@code null}
 * @param messageSeq 이 행동이 만든 대화 메시지의 순번. 메시지를 만들지 않는 {@code SKIP}·{@code SESSION_END} 는 {@code
 *     null}
 * @param responseLatencyMs 질문 제시({@code QUESTION_SHOWN} 의 {@code occurredAt})부터 이 행동까지의 소요 시간(ms).
 *     선행 {@code QUESTION_SHOWN} 이 없으면 {@code null} — 추정하지 않는다
 * @param selectedOptionCount 고른 칩의 <b>개수</b>. 무엇을 골랐는지는 남기지 않는다. {@code ANSWER_CHIP} 외에는 {@code
 *     null}
 * @param directTextProvided 칩과 함께 직접 입력을 곁들였는지 <b>여부만</b>. 내용은 남기지 않는다. {@code ANSWER_CHIP} 외에는
 *     {@code null}
 * @param recordingDurationMs 녹음 길이(ms). 클라이언트가 보고한 녹음 시작·종료 시각의 차이다. {@code ANSWER_VOICE} 외에는
 *     {@code null}
 * @param stopReason 녹음이 끝난 사유({@code SILENCE}·{@code USER_FINISH}·{@code TIMEOUT}). {@code
 *     ANSWER_VOICE} 외에는 {@code null}
 * @param reason 건너뛴·종료한 사유({@code ConversationCompletionReason}). {@code SKIP} 은 생략 가능해 {@code
 *     null} 일 수 있고, 그 밖의 종류는 {@code SESSION_END} 를 빼면 {@code null}
 * @param questionCount 종료 시점까지 이 대화가 던진 질문 수. {@code SESSION_END} 외에는 {@code null}
 * @param occurredAt 서버가 이 행동을 관측한 시각
 * @param expireAt TTL 만료 시각. {@code occurredAt + app.conversation-event.retention-days}
 */
@Document(collection = "conversation_events")
public record ConversationEventDocument(
    @Id String id,
    Long sessionId,
    long seq,
    Long childId,
    Long drawingSessionId,
    ConversationEventType eventType,
    Long questionMessageId,
    Integer questionSeq,
    Integer messageSeq,
    Long responseLatencyMs,
    Integer selectedOptionCount,
    Boolean directTextProvided,
    Long recordingDurationMs,
    String stopReason,
    String reason,
    Integer questionCount,
    Instant occurredAt,
    Instant expireAt) {}
