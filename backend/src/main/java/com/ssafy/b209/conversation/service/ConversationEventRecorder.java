package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.config.ConversationEventRetentionProperties;
import com.ssafy.b209.conversation.document.ConversationEventDocument;
import com.ssafy.b209.conversation.document.ConversationEventType;
import com.ssafy.b209.conversation.repository.ConversationEventDocumentRepository;
import com.ssafy.b209.conversation.repository.ConversationEventSequenceRepository;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.function.Consumer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 대화 흐름에서 일어난 행동을 MongoDB {@code conversation_events} 로 적재한다 (S15P11B209-973).
 *
 * <p><b>① 절대 대화를 막지 않는다.</b> 모든 적재는 예외를 삼키고 경고만 남긴다. 이 화면은 아이가 쓰는 화면이다 — 관측용 로그를 못 남겼다고 아이 앞에서 질문이
 * 멈추거나 답변 업로드가 500 이 되면, 잃는 것(대화)이 지키는 것(통계)보다 훨씬 크다. 유실된 이벤트는 그 자리에서 로그로 알 수 있고 소비자는 결측을 견디도록
 * 설계한다.
 *
 * <p><b>② 커밋 이후에 쓴다.</b> 호출부는 MySQL Transaction 안에서 돌고, 그 안에는 대화 세션 행에 대한 <b>비관 잠금</b>이 걸려 있다
 * ({@code findByIdForUpdate}). Transaction 안에서 Mongo 를 호출하면 (a) 잠금을 쥔 채 다른 저장소를 왕복해 같은 대화의 다음 요청을
 * 그만큼 세우고, (b) 이후 단계가 실패해 Rollback 되면 <b>일어나지 않은 행동</b>의 이벤트만 남는다. Mongo 는 MySQL Transaction 에 참여하지
 * 않으므로 되돌릴 방법이 없다. 그래서 등록만 해 두고 커밋이 확정된 뒤에 쓴다 ({@code StrokeBatchDeletionService} 와 같은 규칙).
 *
 * <p><b>③ 시각은 커밋 시각이 아니라 관측 시각이다.</b> {@code occurredAt} 은 커밋 이후 실행되는 람다 안이 아니라 <b>호출된 순간</b>에 찍는다.
 * 커밋 시점에 찍으면 커밋을 기다린 시간이 응답 지연에 섞여 들어간다.
 *
 * <p><b>④ 발화 내용은 넣지 않는다.</b> 이 클래스의 어떤 메서드도 텍스트·전사·칩 라벨을 받지 않는다. 파라미터 목록이 곧 방어선이다 (CLAUDE.md 9절 ·
 * {@link ConversationEventDocument} 주석).
 */
@Service
public class ConversationEventRecorder {

  private static final Logger log = LoggerFactory.getLogger(ConversationEventRecorder.class);

  private final ConversationEventDocumentRepository eventRepository;
  private final ConversationEventSequenceRepository sequenceRepository;
  private final ConversationEventRetentionProperties retentionProperties;
  private final Clock clock;

  /**
   * 이벤트 적재에 필요한 저장소·보관 정책·시계를 구성한다.
   *
   * @param eventRepository 대화 행동 이벤트 문서 Repository
   * @param sequenceRepository 이벤트 순번 발급 Repository
   * @param retentionProperties 보관 기간 설정
   * @param clock 행동 관측 시각
   */
  public ConversationEventRecorder(
      ConversationEventDocumentRepository eventRepository,
      ConversationEventSequenceRepository sequenceRepository,
      ConversationEventRetentionProperties retentionProperties,
      Clock clock) {
    this.eventRepository = eventRepository;
    this.sequenceRepository = sequenceRepository;
    this.retentionProperties = retentionProperties;
    this.clock = clock;
  }

  /**
   * AI 질문이 저장돼 화면으로 내려간 것을 기록한다.
   *
   * <p>이 이벤트의 {@code occurredAt} 이 뒤따르는 답변·건너뛰기의 <b>응답 지연 기준점</b>이다. 이것이 빠지면 그 질문에 대한 지연은 계산되지 않고
   * {@code null} 로 남는다 — 추정값으로 메우지 않는다.
   *
   * @param context 대화·아동·활동 좌표
   * @param questionMessageId 저장된 질문 메시지 식별자
   * @param messageSeq 질문의 대화 내 순번
   */
  public void recordQuestionShown(
      ConversationEventContext context, Long questionMessageId, int messageSeq) {
    Instant occurredAt = clock.instant();
    record(
        context,
        ConversationEventType.QUESTION_SHOWN,
        occurredAt,
        builder ->
            builder
                .questionMessageId(questionMessageId)
                // 질문 자신이 기준점이므로 선행 이벤트를 찾지 않는다 — 두 순번이 같은 값이다.
                .questionSeq(messageSeq)
                .messageSeq(messageSeq));
  }

  /**
   * 아이가 마이크로 답한 것을 기록한다.
   *
   * <p>녹음이 시간 초과로 끝난 경우도 여기 {@code stopReason=TIMEOUT} 으로 남는다 — 별도의 timeout 이벤트를 두지 않는 이유는 {@link
   * ConversationEventType} 주석 참고.
   *
   * @param context 대화·아동·활동 좌표
   * @param questionMessageId 답변이 겨냥한 질문 메시지 식별자
   * @param messageSeq 답변의 대화 내 순번
   * @param clientStartedAt 클라이언트가 보고한 녹음 시작 시각
   * @param clientEndedAt 클라이언트가 보고한 녹음 종료 시각
   * @param stopReason 녹음을 끝낸 사유
   */
  public void recordVoiceAnswer(
      ConversationEventContext context,
      Long questionMessageId,
      int messageSeq,
      Instant clientStartedAt,
      Instant clientEndedAt,
      String stopReason) {
    Instant occurredAt = clock.instant();
    Long recordingDurationMs = durationMs(clientStartedAt, clientEndedAt);
    record(
        context,
        ConversationEventType.ANSWER_VOICE,
        occurredAt,
        builder ->
            builder
                .questionMessageId(questionMessageId)
                .messageSeq(messageSeq)
                .recordingDurationMs(recordingDurationMs)
                .stopReason(stopReason));
  }

  /**
   * 아이가 선택 칩으로 답한 것을 기록한다.
   *
   * @param context 대화·아동·활동 좌표
   * @param questionMessageId 답변이 겨냥한 질문 메시지 식별자
   * @param messageSeq 답변의 대화 내 순번
   * @param selectedOptionCount 고른 칩의 개수. <b>무엇을 골랐는지는 받지 않는다</b>
   * @param directTextProvided 직접 입력을 곁들였는지 여부. <b>내용은 받지 않는다</b>
   */
  public void recordOptionAnswer(
      ConversationEventContext context,
      Long questionMessageId,
      int messageSeq,
      int selectedOptionCount,
      boolean directTextProvided) {
    Instant occurredAt = clock.instant();
    record(
        context,
        ConversationEventType.ANSWER_CHIP,
        occurredAt,
        builder ->
            builder
                .questionMessageId(questionMessageId)
                .messageSeq(messageSeq)
                .selectedOptionCount(selectedOptionCount)
                .directTextProvided(directTextProvided));
  }

  /**
   * 아이가 질문을 건너뛴 것을 기록한다.
   *
   * <p>메시지를 만들지 않는 행동이라 {@code messageSeq} 는 비운다. 질문 자체의 순번은 선행 {@code QUESTION_SHOWN} 에서 채운다.
   *
   * @param context 대화·아동·활동 좌표
   * @param questionMessageId 건너뛴 질문 메시지 식별자
   * @param reason 건너뛴 사유. 생략 가능하므로 {@code null} 일 수 있다
   */
  public void recordSkip(ConversationEventContext context, Long questionMessageId, String reason) {
    Instant occurredAt = clock.instant();
    record(
        context,
        ConversationEventType.SKIP,
        occurredAt,
        builder -> builder.questionMessageId(questionMessageId).reason(reason));
  }

  /**
   * 대화가 종료된 것을 기록한다.
   *
   * <p>질문에 딸린 행동이 아니라 대화 전체의 종결이므로 {@code questionMessageId}·응답 지연이 없다.
   *
   * @param context 대화·아동·활동 좌표
   * @param reason 종료 사유
   * @param questionCount 종료 시점까지 던진 질문 수
   */
  public void recordSessionEnd(ConversationEventContext context, String reason, int questionCount) {
    Instant occurredAt = clock.instant();
    record(
        context,
        ConversationEventType.SESSION_END,
        occurredAt,
        builder -> builder.reason(reason).questionCount(questionCount));
  }

  /**
   * 이벤트 한 건을 커밋 이후에 적재하도록 등록한다.
   *
   * @param context 대화·아동·활동 좌표
   * @param eventType 행동의 종류
   * @param occurredAt 호출 시점에 찍은 관측 시각
   * @param customizer 종류별 필드를 채우는 조립기
   */
  private void record(
      ConversationEventContext context,
      ConversationEventType eventType,
      Instant occurredAt,
      Consumer<ConversationEventDraft> customizer) {
    ConversationEventDraft draft = new ConversationEventDraft(context, eventType, occurredAt);
    customizer.accept(draft);
    afterCommit(() -> write(draft));
  }

  /**
   * 조립된 이벤트를 실제로 적재한다.
   *
   * <p>응답 지연과 질문 순번은 여기서 선행 {@code QUESTION_SHOWN} 을 찾아 채운다. 찾지 못하면 두 값 모두 {@code null} 로 둔다 — 적재가
   * best-effort 라 선행 이벤트가 없을 수 있고, 없는 것을 추정으로 메우면 소비자가 결측과 실측을 구분하지 못한다.
   *
   * @param draft 조립된 이벤트
   */
  private void write(ConversationEventDraft draft) {
    Instant occurredAt = draft.occurredAt;
    Optional<ConversationEventDocument> shown = findQuestionShown(draft);
    eventRepository.insert(
        new ConversationEventDocument(
            null,
            draft.context.conversationSessionId(),
            sequenceRepository.next(),
            draft.context.childId(),
            draft.context.drawingSessionId(),
            draft.eventType,
            draft.questionMessageId,
            draft.eventType == ConversationEventType.QUESTION_SHOWN
                ? draft.questionSeq
                : shown.map(ConversationEventDocument::questionSeq).orElse(null),
            draft.messageSeq,
            shown.map(event -> durationMs(event.occurredAt(), occurredAt)).orElse(null),
            draft.selectedOptionCount,
            draft.directTextProvided,
            draft.recordingDurationMs,
            draft.stopReason,
            draft.reason,
            draft.questionCount,
            occurredAt,
            occurredAt.plus(retentionProperties.retention())));
  }

  private Optional<ConversationEventDocument> findQuestionShown(ConversationEventDraft draft) {
    if (draft.eventType == ConversationEventType.QUESTION_SHOWN
        || draft.questionMessageId == null) {
      return Optional.empty();
    }
    return eventRepository.findFirstBySessionIdAndQuestionMessageIdAndEventTypeOrderBySeqAsc(
        draft.context.conversationSessionId(),
        draft.questionMessageId,
        ConversationEventType.QUESTION_SHOWN);
  }

  private static Long durationMs(Instant from, Instant to) {
    if (from == null || to == null) {
      return null;
    }
    return Duration.between(from, to).toMillis();
  }

  /**
   * Transaction 이 있으면 Commit 이후에, 없으면 즉시 실행한다. 어느 쪽이든 실패는 밖으로 던지지 않는다.
   *
   * <p><b>왜 삼키는가</b>: 이 시점에는 대화 쪽 MySQL 저장이 <b>이미 Commit 됐다.</b> 여기서 예외를 던지면 Spring 이 그것을 호출자에게 전파해
   * <b>답변은 저장됐는데 화면에는 실패</b>가 뜬다. 아이는 같은 답을 다시 하려 하고, 서버는 중복 답변으로 거절한다 — 관측 로그 하나를 못 남긴 대가로 대화가
   * 끊긴다. 대신 WARN 으로 남겨 유실을 추적 가능하게 하고, 남은 것은 소비자가 결측으로 처리한다.
   *
   * @param action 실행할 적재 작업
   */
  private void afterCommit(Runnable action) {
    if (!TransactionSynchronizationManager.isSynchronizationActive()) {
      runSafely(action);
      return;
    }
    TransactionSynchronizationManager.registerSynchronization(
        new TransactionSynchronization() {
          @Override
          public void afterCommit() {
            runSafely(action);
          }
        });
  }

  private void runSafely(Runnable action) {
    try {
      action.run();
    } catch (RuntimeException exception) {
      // 식별자만 남긴다. 이 클래스는 발화 내용을 애초에 받지 않으므로 로그로 샐 내용도 없다.
      log.warn(
          "대화 행동 이벤트 적재에 실패해 이번 행동은 기록되지 않습니다. reason={}", exception.getClass().getSimpleName());
    }
  }

  /**
   * 조립 중인 이벤트다. 종류마다 채우는 필드가 달라 18개짜리 생성자를 호출부마다 반복하지 않기 위한 내부 가변 홀더이며, {@link #write} 직전까지만 산다.
   */
  private static final class ConversationEventDraft {

    private final ConversationEventContext context;
    private final ConversationEventType eventType;
    private final Instant occurredAt;

    private Long questionMessageId;
    private Integer questionSeq;
    private Integer messageSeq;
    private Integer selectedOptionCount;
    private Boolean directTextProvided;
    private Long recordingDurationMs;
    private String stopReason;
    private String reason;
    private Integer questionCount;

    private ConversationEventDraft(
        ConversationEventContext context, ConversationEventType eventType, Instant occurredAt) {
      this.context = context;
      this.eventType = eventType;
      this.occurredAt = occurredAt;
    }

    private ConversationEventDraft questionMessageId(Long value) {
      this.questionMessageId = value;
      return this;
    }

    private ConversationEventDraft questionSeq(Integer value) {
      this.questionSeq = value;
      return this;
    }

    private ConversationEventDraft messageSeq(Integer value) {
      this.messageSeq = value;
      return this;
    }

    private ConversationEventDraft selectedOptionCount(Integer value) {
      this.selectedOptionCount = value;
      return this;
    }

    private ConversationEventDraft directTextProvided(Boolean value) {
      this.directTextProvided = value;
      return this;
    }

    private ConversationEventDraft recordingDurationMs(Long value) {
      this.recordingDurationMs = value;
      return this;
    }

    private ConversationEventDraft stopReason(String value) {
      this.stopReason = value;
      return this;
    }

    private ConversationEventDraft reason(String value) {
      this.reason = value;
      return this;
    }

    private ConversationEventDraft questionCount(Integer value) {
      this.questionCount = value;
      return this;
    }
  }
}
