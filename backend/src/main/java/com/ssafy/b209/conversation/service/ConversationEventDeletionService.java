package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.repository.ConversationEventDocumentRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 아동·활동 삭제에 맞춰 MongoDB에 남은 대화 행동 이벤트를 즉시 지운다 (S15P11B209-973).
 *
 * <p><b>왜 TTL 을 기다리지 않는가</b>: TTL 은 "언젠가 지운다"이지 즉시가 아니다(mongod 가 60초마다 훑고, 부하가 있으면 더 늦다). 아동 삭제·회원
 * 탈퇴는 동의 철회의 성격이므로 기다리지 않고 지운다 (CLAUDE.md 9절 · 저장소-아키텍처 §5). {@code StrokeBatchDeletionService} 와
 * 같은 규칙이며, 이유·주의점도 그 클래스 주석과 동일하다.
 *
 * <p><b>⚠️ 왜 Commit 이후인가</b>: 호출자는 MySQL Transaction 안에서 돈다. Mongo 는 그 Transaction 에 참여하지 않으므로,
 * 트랜잭션 도중에 지워 버리면 이후 단계가 실패해 Rollback 됐을 때 되돌릴 방법이 없다 — 멀쩡히 살아 있는 아동의 대화 기록만 사라진다.
 */
@Service
public class ConversationEventDeletionService {

  private static final Logger log = LoggerFactory.getLogger(ConversationEventDeletionService.class);

  private final ConversationEventDocumentRepository eventRepository;

  /**
   * 이벤트 삭제에 필요한 Repository를 주입한다.
   *
   * @param eventRepository 대화 행동 이벤트 문서 Repository
   */
  public ConversationEventDeletionService(ConversationEventDocumentRepository eventRepository) {
    this.eventRepository = eventRepository;
  }

  /**
   * 한 아동의 대화 행동 이벤트를 Commit 이후 전부 삭제한다.
   *
   * @param childId 삭제된 아동 ID
   */
  public void deleteByChild(long childId) {
    afterCommit(
        () -> {
          long deleted = eventRepository.deleteByChildId(childId);
          log.info("삭제된 아동의 대화 행동 이벤트를 정리했습니다. childId={}, deleted={}", childId, deleted);
        });
  }

  /**
   * 한 그림 활동에 딸린 대화 행동 이벤트를 Commit 이후 삭제한다.
   *
   * <p>{@code childId} 를 함께 넘겨 인덱스를 타게 한다 — 이유는 {@code
   * ConversationEventDocumentRepository#deleteByChildIdAndDrawingSessionId} 주석 참고.
   *
   * @param childId 활동을 소유한 아동 ID
   * @param drawingSessionId 삭제된 그림 활동 세션 ID
   */
  public void deleteByDrawingSession(long childId, long drawingSessionId) {
    afterCommit(
        () -> {
          long deleted =
              eventRepository.deleteByChildIdAndDrawingSessionId(childId, drawingSessionId);
          log.info(
              "삭제된 그림 활동의 대화 행동 이벤트를 정리했습니다. drawingSessionId={}, deleted={}",
              drawingSessionId,
              deleted);
        });
  }

  /**
   * Transaction 이 있으면 Commit 이후에, 없으면 즉시 실행한다.
   *
   * <p><b>⚠️ 실패를 밖으로 던지지 않는다.</b> 이 시점에는 MySQL 삭제가 이미 Commit 됐다. 여기서 예외를 던지면 <b>탈퇴가 성공했는데 응답은
   * 500</b> 이 된다 — 사용자는 실패로 알고 다시 시도하지만 계정이 없으니 404를 받고, Mongo 문서는 어차피 지워지지 않은 채다. 대신 ERROR 로 남긴다.
   * 남은 문서는 TTL 이 최종 안전망으로 회수하며, 로그의 식별자로 운영자가 즉시 정리할 수 있다.
   *
   * @param action 실행할 삭제 작업
   */
  private void afterCommit(Runnable action) {
    if (!TransactionSynchronizationManager.isSynchronizationActive()) {
      action.run();
      return;
    }
    TransactionSynchronizationManager.registerSynchronization(
        new TransactionSynchronization() {
          @Override
          public void afterCommit() {
            try {
              action.run();
            } catch (RuntimeException exception) {
              log.error(
                  "대화 행동 이벤트 동반 삭제에 실패했습니다. MySQL 삭제는 이미 확정됐으므로 남은 문서를 수동 정리해야 합니다.", exception);
            }
          }
        });
  }
}
