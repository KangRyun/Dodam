package com.ssafy.b209.drawing.service;

import com.ssafy.b209.drawing.repository.StrokeBatchDocumentRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 세션·아동 삭제에 맞춰 MongoDB에 남은 그리기 과정 데이터를 즉시 지운다 (S15P11B209-365).
 *
 * <p><b>왜 TTL 을 기다리지 않는가</b>: TTL 은 "언젠가 지운다"이지 즉시가 아니다(mongod 가 60초마다 훑고, 부하가 있으면 더 늦다). 아동 삭제·회원
 * 탈퇴는 동의 철회의 성격이므로 기다리지 않고 지운다 (CLAUDE.md 9절 · 저장소-아키텍처 §5).
 *
 * <p><b>⚠️ 왜 Commit 이후인가</b>: 호출자(아동 삭제·세션 삭제·회원 탈퇴)는 MySQL Transaction 안에서 돈다. Mongo 는 그
 * Transaction 에 참여하지 않으므로, 트랜잭션 도중에 지워 버리면 <b>이후 단계가 실패해 Rollback 됐을 때 되돌릴 방법이 없다</b> — 멀쩡히 살아 있는
 * 아동의 그림 과정 데이터만 사라진다. 실제로 회원 탈퇴 경로는 아동 삭제 <i>이후</i>에 전문가 프로필·사용자 삭제가 이어지고, 그 구간에서 FK 제약으로 실패한 전례가
 * 있다 (S15P11B209-728). 그래서 "MySQL 삭제가 확정된 뒤에만" 지운다.
 *
 * <p>Commit 직후에 프로세스가 죽으면 문서가 남을 수 있다. 그 경우에도 TTL 이 최종 안전망으로 남으며, 남은 문서는 소유 세션이 이미 삭제 상태라 조회 경로로
 * 노출되지 않는다.
 */
@Service
public class StrokeBatchDeletionService {

  private static final Logger log = LoggerFactory.getLogger(StrokeBatchDeletionService.class);

  private final StrokeBatchDocumentRepository strokeBatchDocumentRepository;

  /**
   * Stroke 문서 삭제에 필요한 Repository를 주입한다.
   *
   * @param strokeBatchDocumentRepository Stroke 배치 문서 Repository
   */
  public StrokeBatchDeletionService(StrokeBatchDocumentRepository strokeBatchDocumentRepository) {
    this.strokeBatchDocumentRepository = strokeBatchDocumentRepository;
  }

  /**
   * 한 그림 활동의 Stroke 배치를 Commit 이후 삭제한다.
   *
   * @param drawingSessionId 삭제된 그림 활동 세션 ID
   */
  public void deleteByDrawingSession(long drawingSessionId) {
    afterCommit(
        () -> {
          long deleted = strokeBatchDocumentRepository.deleteBySessionId(drawingSessionId);
          log.info(
              "삭제된 그림 활동의 Stroke 배치를 정리했습니다. drawingSessionId={}, deleted={}",
              drawingSessionId,
              deleted);
        });
  }

  /**
   * 한 아동의 Stroke 배치를 Commit 이후 삭제한다.
   *
   * @param childId 삭제된 아동 ID
   */
  public void deleteByChild(long childId) {
    afterCommit(
        () -> {
          long deleted = strokeBatchDocumentRepository.deleteByChildId(childId);
          log.info("삭제된 아동의 Stroke 배치를 정리했습니다. childId={}, deleted={}", childId, deleted);
        });
  }

  /**
   * Transaction 이 있으면 Commit 이후에, 없으면 즉시 실행한다.
   *
   * <p><b>⚠️ 실패를 밖으로 던지지 않는다.</b> 이 시점에는 MySQL 삭제가 <b>이미 Commit 됐다.</b> 여기서 예외를 던지면 Spring 이 그것을 호출자에게
   * 전파해 <b>탈퇴가 성공했는데 응답은 500</b> 이 된다. 사용자는 실패로 알고 다시 시도하지만 계정이 없으니 404를 받는다 — 게다가 Mongo 문서는 어차피 지워지지
   * 않은 채다. 즉 던지면 <b>UX 와 데이터 양쪽에서 더 나쁘다.</b>
   *
   * <p>대신 ERROR 로 남긴다. 남은 문서는 TTL 이 최종 안전망으로 회수하며, 로그의 식별자로 운영자가 즉시 정리할 수 있다.
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
                  "Stroke 배치 동반 삭제에 실패했습니다. MySQL 삭제는 이미 확정됐으므로 남은 문서를 수동 정리해야 합니다.",
                  exception);
            }
          }
        });
  }
}
