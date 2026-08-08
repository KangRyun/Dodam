package com.ssafy.b209.report.service;

import java.time.Duration;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

/**
 * {@code report_generation_retries} 대기열을 채우고 선점한다 (S15P11B209 P0-2).
 *
 * <p><strong>대기열은 스스로 채운다.</strong> 실패한 쪽이 "재시도해 줘"를 따로 넣지 않는다 — 넣는 순간과 실패를 기록하는 순간 사이에서 프로세스가
 * 죽으면 그 리포트는 {@code FAILED_RETRYABLE}인 채로 아무도 다시 보지 않는다. 대신 {@link #adopt(int)}가 {@code reports}를 직접
 * 읽어 대기열 행을 만든다. 진실은 리포트 상태 한 곳에만 있고, 이 표는 몇 번 시도했고 다음이 언제인지만 들고 간다.
 *
 * <p>backend는 replicas 2라 워커가 두 벌 돈다. {@link #claim(int, Duration, int)}의 {@code for update skip
 * locked}가 한 작업을 한 파드만 집게 한다 — 이것 없이 조회 후 갱신하면 두 파드가 같은 리포트를 동시에 다시 만든다.
 *
 * <p>선점에 임대 컬럼을 따로 두지 않고 {@code next_attempt_at}을 앞으로 민다. 워커가 도중에 죽어도 그 시각이 지나면 다음 실행이 자연히 다시 집는다 —
 * 멈춰 있는 작업을 풀어 주는 코드가 필요 없다.
 */
@Repository
public class ReportGenerationRetryRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * @param jdbcTemplate 대기열 테이블 접근 Template
   */
  public ReportGenerationRetryRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 대기열에 아직 없는 재시도 가능 실패 리포트를 대기열에 올린다.
   *
   * <p>{@code FAILED_FINAL}과 재시도 판단이 없는 옛 {@code FAILED}는 집지 않는다. 뒤엣것을 집으면 활동·리포트를 떼어 놓기 전에 쌓인 실패가
   * 배포 직후 한꺼번에 AI로 몰린다.
   *
   * @param limit 한 번에 올릴 최대 건수
   * @return 새로 올린 건수
   */
  @Transactional
  public int adopt(int limit) {
    if (limit <= 0) {
      return 0;
    }
    return jdbcTemplate.update(
        """
        insert into report_generation_retries
               (report_id, analysis_id, attempt_count, next_attempt_at, last_failure_code)
        select report.id, report.analysis_id, 0, current_timestamp(6), report.failure_reason
          from reports report
          left join report_generation_retries queued on queued.report_id = report.id
         where report.report_status = 'FAILED_RETRYABLE'
           and queued.id is null
         order by report.id
         limit ?
        """,
        limit);
  }

  /**
   * 시각이 된 작업을 배치 크기만큼 선점한다.
   *
   * <p>선점과 조회가 한 트랜잭션이어야 잠금이 유지된다 — {@link Transactional}을 떼면 조용히 깨진다.
   *
   * <p>다음 시각은 {@code lease × 시도 횟수}만큼 뒤로 민다. 상류가 흔들려 실패한 것이라면 곧바로 같은 간격으로 다시 두드리는 게 상황을 더 나쁘게 만든다.
   *
   * @param batchSize 한 번에 선점할 최대 건수
   * @param lease 다음 시도까지 미뤄 둘 기본 간격
   * @param maxAttempts 이 횟수를 넘긴 작업은 선점하지 않는다
   * @return 선점된 작업 목록이며 없으면 빈 목록
   */
  @Transactional
  public List<ReportGenerationRetry> claim(int batchSize, Duration lease, int maxAttempts) {
    if (batchSize <= 0) {
      return List.of();
    }
    List<ReportGenerationRetry> claimed =
        jdbcTemplate.query(
            """
            select queued.id, queued.report_id, queued.analysis_id,
                   queued.attempt_count, queued.correlation_id
              from report_generation_retries queued
              join reports report on report.id = queued.report_id
             where queued.resolved_at is null
               and queued.attempt_count < ?
               and queued.next_attempt_at <= current_timestamp(6)
               and report.report_status = 'FAILED_RETRYABLE'
             order by queued.next_attempt_at
             limit ?
             for update skip locked
            """,
            (rs, rowNum) ->
                new ReportGenerationRetry(
                    rs.getLong("id"),
                    rs.getLong("report_id"),
                    rs.getLong("analysis_id"),
                    rs.getInt("attempt_count") + 1,
                    rs.getString("correlation_id")),
            maxAttempts,
            batchSize);
    for (ReportGenerationRetry retry : claimed) {
      jdbcTemplate.update(
          """
          update report_generation_retries
             set attempt_count = attempt_count + 1,
                 next_attempt_at = date_add(current_timestamp(6), interval ? second)
           where id = ?
          """,
          Math.max(1L, lease.getSeconds()) * retry.attemptCount(),
          retry.id());
    }
    return claimed;
  }

  /**
   * 이번 시도가 남긴 실패를 기록한다.
   *
   * @param retryId 재시도 작업 식별자
   * @param failure 원문을 포함하지 않는 실패 정보
   */
  @Transactional
  public void recordFailure(long retryId, ReportGenerationFailure failure) {
    jdbcTemplate.update(
        """
        update report_generation_retries
           set last_failure_stage = ?,
               last_failure_code = ?,
               correlation_id = ?
         where id = ?
        """,
        failure.stage().name(),
        failure.code(),
        failure.correlationId(),
        retryId);
  }

  /**
   * 작업을 대기열에서 내린다.
   *
   * <p>성공했든 시도 한도를 넘겨 포기했든 같은 처리다. 행은 남겨 둔다 — 몇 번 만에 됐는지, 무엇 때문에 포기했는지가 다음에 이 자리를 볼 사람에게 필요하다.
   *
   * @param retryId 재시도 작업 식별자
   */
  @Transactional
  public void resolve(long retryId) {
    jdbcTemplate.update(
        "update report_generation_retries set resolved_at = current_timestamp(6) where id = ?",
        retryId);
  }

  /**
   * 시도 한도를 다 쓴 작업을 최종 실패로 내린다.
   *
   * <p>리포트 상태까지 {@code FAILED_FINAL}로 옮긴다. 상태를 그대로 두면 {@link #adopt(int)}가 다시 집으려 하고, 보호자 화면도 언젠가는
   * 될 것처럼 계속 보인다.
   *
   * @param maxAttempts 포기 기준이 되는 시도 횟수
   * @return 포기 처리한 건수
   */
  @Transactional
  public int abandonExhausted(int maxAttempts) {
    int abandoned =
        jdbcTemplate.update(
            """
            update reports report
              join report_generation_retries queued on queued.report_id = report.id
               set report.report_status = 'FAILED_FINAL'
             where queued.resolved_at is null
               and queued.attempt_count >= ?
               and report.report_status = 'FAILED_RETRYABLE'
            """,
            maxAttempts);
    jdbcTemplate.update(
        """
        update report_generation_retries
           set resolved_at = current_timestamp(6)
         where resolved_at is null
           and attempt_count >= ?
        """,
        maxAttempts);
    return abandoned;
  }
}
