package com.ssafy.b209.storage.deletion;

import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

/**
 * {@code storage_deletion_jobs} 큐를 선점·기록한다 (S15P11B209-780).
 *
 * <p>⚠️ 이 저장소는 <b>DB 만</b> 다룬다. 실제 파일 삭제는 트랜잭션 밖에서 일어나야 한다 — 트랜잭션 안에서 Storage 를 부르면 이후 롤백 시 파일만
 * 지워진 고아 상태가 되고, DB 는 되돌아가도 파일은 못 되돌린다(373 체크리스트의 "DB 트랜잭션과 분리된 파일 삭제").
 *
 * <p>backend 는 replicas 2 라 워커가 두 벌 돈다. {@link #claim(int)} 의 원자적 UPDATE 가 한 잡을 한 파드만 집게 한다.
 */
@Repository
public class StorageDeletionJobRepository {

  private final JdbcTemplate jdbcTemplate;

  public StorageDeletionJobRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * PENDING 잡을 배치 크기만큼 PROCESSING 으로 선점하고 그 목록을 돌려준다.
   *
   * <p>{@code for update skip locked}(MySQL 8+) 로 다른 파드가 이미 잠근 행을 건너뛴다. 두 파드가 동시에 실행돼도 서로 다른 잡을
   * 집고, 상대를 기다리지도 않는다. 이것 없이 조회 후 갱신하면 두 파드가 같은 행을 읽어 retry_count 가 이중 증가하고 조기에 FAILED 로 떨어진다
   * (파일 삭제 자체는 멱등이라 데이터는 안전하다).
   *
   * <p>선점과 조회가 한 트랜잭션이어야 잠금이 유지된다 — {@link Transactional} 을 떼면 조용히 깨진다.
   *
   * @param batchSize 한 번에 선점할 최대 건수
   * @return 선점된 잡 목록. 없으면 빈 목록
   */
  @Transactional
  public List<StorageDeletionJob> claim(int batchSize) {
    if (batchSize <= 0) {
      return List.of();
    }
    List<StorageDeletionJob> jobs =
        jdbcTemplate.query(
            """
            select id, storage_key, resource_type, retry_count
              from storage_deletion_jobs
             where deletion_status = 'PENDING'
             order by requested_at
             limit ?
             for update skip locked
            """,
            (rs, rowNum) ->
                new StorageDeletionJob(
                    rs.getLong("id"),
                    rs.getString("storage_key"),
                    rs.getString("resource_type"),
                    rs.getInt("retry_count")),
            batchSize);
    if (jobs.isEmpty()) {
      return List.of();
    }
    String placeholders = jobs.stream().map(job -> "?").collect(java.util.stream.Collectors.joining(","));
    Object[] ids = jobs.stream().map(StorageDeletionJob::id).toArray();
    jdbcTemplate.update(
        """
        update storage_deletion_jobs
           set deletion_status = 'PROCESSING',
               last_attempted_at = current_timestamp(6)
         where id in (%s)
        """
            .formatted(placeholders),
        ids);
    return jobs;
  }

  /**
   * 삭제에 성공한 잡을 완료 처리한다.
   *
   * @param jobId 잡 ID
   */
  public void markCompleted(long jobId) {
    jdbcTemplate.update(
        """
        update storage_deletion_jobs
           set deletion_status = 'COMPLETED',
               completed_at = current_timestamp(6),
               error_code = null
         where id = ?
        """,
        jobId);
  }

  /**
   * 삭제에 실패한 잡을 다시 시도하도록 PENDING 으로 되돌리고 재시도 횟수를 올린다.
   *
   * @param jobId 잡 ID
   * @param errorCode 마지막 오류 코드(원문 메시지가 아니라 분류용 짧은 코드)
   */
  public void markRetry(long jobId, String errorCode) {
    jdbcTemplate.update(
        """
        update storage_deletion_jobs
           set deletion_status = 'PENDING',
               retry_count = retry_count + 1,
               error_code = ?
         where id = ?
        """,
        truncate(errorCode),
        jobId);
  }

  /**
   * 재시도 예산을 소진했거나 처리할 수 없는 잡을 실패로 확정한다.
   *
   * <p>행을 지우지 않는 이유: 이 목록이 "무엇이 안 지워졌는가"의 유일한 기록이다. 지우면 미삭제 파일을 나중에 찾을 방법이 없다(가드레일 9절).
   *
   * @param jobId 잡 ID
   * @param errorCode 실패 사유 코드
   */
  public void markFailed(long jobId, String errorCode) {
    jdbcTemplate.update(
        """
        update storage_deletion_jobs
           set deletion_status = 'FAILED',
               retry_count = retry_count + 1,
               error_code = ?
         where id = ?
        """,
        truncate(errorCode),
        jobId);
  }

  /**
   * 선점된 채 방치된 잡을 PENDING 으로 되돌린다.
   *
   * <p>파드가 배포·OOM 으로 죽으면 그 파드가 집은 잡은 PROCESSING 에 갇힌다. 회수가 없으면 그 파일은 영원히 안 지워진다.
   *
   * @param stuckSeconds 이 시간(초)을 넘게 PROCESSING 인 잡을 회수 대상으로 본다
   * @return 회수된 건수
   */
  public int releaseStuck(long stuckSeconds) {
    return jdbcTemplate.update(
        """
        update storage_deletion_jobs
           set deletion_status = 'PENDING'
         where deletion_status = 'PROCESSING'
           and last_attempted_at < date_sub(current_timestamp(6), interval ? second)
        """,
        stuckSeconds);
  }

  /** error_code 컬럼은 VARCHAR(80) 이다. 길이를 넘기면 UPDATE 자체가 실패해 잡이 갇힌다. */
  private String truncate(String errorCode) {
    if (errorCode == null) {
      return null;
    }
    return errorCode.length() <= 80 ? errorCode : errorCode.substring(0, 80);
  }
}
