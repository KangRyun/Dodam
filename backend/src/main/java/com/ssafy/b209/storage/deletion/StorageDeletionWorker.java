package com.ssafy.b209.storage.deletion;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * {@code storage_deletion_jobs} 를 소비해 실제 파일을 삭제한다 (S15P11B209-780).
 *
 * <p><b>왜 이 워커가 필요한가.</b> 회원 탈퇴·아동 삭제·그림 세션 삭제는 삭제할 파일을 이 테이블에 등록만 하고 끝낸다(생산자 5곳). 그런데 이 테이블을
 * 읽어 실제로 지우는 코드가 없어서, 잡은 쌓이기만 하고 MinIO 의 아동 그림·음성은 무기한 남아 있었다. CLAUDE.md 9절 "회원 탈퇴 시 아동 데이터 함께
 * 삭제"와 어긋나는 상태였다.
 *
 * <p><b>DB 와 파일 삭제를 분리한다.</b> 선점·결과 기록만 트랜잭션이고 파일 삭제는 그 밖에서 한다. 트랜잭션 안에서 Storage 를 부르면 이후 롤백 시
 * 파일만 지워진 고아 상태가 되는데, DB 는 되돌아가도 파일은 못 되돌린다.
 *
 * <p><b>멱등하다.</b> S3 {@code deleteObject} 는 이미 없는 키에도 성공하므로 재시도가 안전하다. 같은 잡을 두 번 처리해도 데이터는 그대로다.
 */
@Component
@ConditionalOnProperty(
    prefix = "app.storage.deletion",
    name = "enabled",
    havingValue = "true",
    matchIfMissing = true)
public class StorageDeletionWorker {

  private static final Logger log = LoggerFactory.getLogger(StorageDeletionWorker.class);

  private final StorageDeletionJobRepository jobRepository;
  private final StorageDeletionRouter router;
  private final StorageDeletionProperties properties;

  public StorageDeletionWorker(
      StorageDeletionJobRepository jobRepository,
      StorageDeletionRouter router,
      StorageDeletionProperties properties) {
    this.jobRepository = jobRepository;
    this.router = router;
    this.properties = properties;
  }

  /**
   * 대기 중인 삭제 작업을 배치 크기만큼 처리한다.
   *
   * <p>개별 실패는 흡수하고 다음 실행에서 다시 시도한다. 한 건이 배치 전체를 멈추면 그 뒤의 아동 데이터가 통째로 안 지워진다.
   */
  @Scheduled(fixedDelayString = "${app.storage.deletion.interval:60s}")
  public void deletePendingObjects() {
    releaseStuckJobs();

    List<StorageDeletionJob> jobs = jobRepository.claim(properties.getBatchSize());
    if (jobs.isEmpty()) {
      return;
    }

    int deleted = 0;
    int retried = 0;
    int failed = 0;
    for (StorageDeletionJob job : jobs) {
      try {
        // ⚠️ 트랜잭션 밖 — 이 호출이 실제 파일을 지운다.
        router.delete(job);
        jobRepository.markCompleted(job.id());
        deleted++;
      } catch (StorageDeletionRouter.UnmappedResourceTypeException exception) {
        // 재시도해도 결과가 같다. 예산을 쓰지 않고 즉시 실패로 확정해 목록에 남긴다.
        jobRepository.markFailed(job.id(), StorageDeletionRouter.UNMAPPED_RESOURCE_TYPE);
        failed++;
        log.error(
            "Storage 삭제: 매핑되지 않은 유형이라 처리할 수 없습니다. jobId={}, resourceType={}",
            job.id(),
            job.resourceType());
      } catch (RuntimeException exception) {
        // ⚠️ storageKey 는 아동 그림·음성 경로다 — 로그에 남기지 않는다(가드레일 9절).
        String errorCode = exception.getClass().getSimpleName();
        if (job.retryCount() + 1 >= properties.getMaxRetryCount()) {
          jobRepository.markFailed(job.id(), errorCode);
          failed++;
          log.error(
              "Storage 삭제: 재시도 예산을 소진해 실패로 확정합니다. jobId={}, resourceType={}, retryCount={}, reason={}",
              job.id(),
              job.resourceType(),
              job.retryCount() + 1,
              errorCode);
        } else {
          jobRepository.markRetry(job.id(), errorCode);
          retried++;
          log.warn(
              "Storage 삭제 실패 — 다음 실행에서 재시도합니다. jobId={}, resourceType={}, retryCount={}, reason={}",
              job.id(),
              job.resourceType(),
              job.retryCount() + 1,
              errorCode);
        }
      }
    }
    log.info(
        "Storage 삭제 배치 완료. claimed={}, deleted={}, retried={}, failed={}",
        jobs.size(),
        deleted,
        retried,
        failed);
  }

  /**
   * 죽은 파드가 선점한 채 남은 잡을 회수한다.
   *
   * <p>회수가 없으면 배포·OOM 으로 파드가 죽을 때마다 그 파드가 집었던 잡이 영구히 PROCESSING 에 갇히고, 해당 아동 파일은 영원히 안 지워진다.
   */
  private void releaseStuckJobs() {
    int released = jobRepository.releaseStuck(properties.getStuckAfter().toSeconds());
    if (released > 0) {
      log.warn("선점된 채 방치된 Storage 삭제 작업을 회수했습니다. count={}", released);
    }
  }
}
