package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.support.IntegrationTestSupport;
import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * 리포트 재시도 대기열이 되살릴 것과 아닌 것을 실제로 가르는지 확인한다 (S15P11B209 P0-2).
 *
 * <p>MySQL에서 도는 이유가 있다. {@code adopt}는 {@code left join ... is null}, {@code claim}은 {@code for
 * update skip locked}, {@code abandonExhausted}는 다중 테이블 UPDATE다 — 셋 다 문법이 맞는지를 실제 엔진만 말해 준다.
 */
class ReportGenerationRetryRepositoryIntegrationTest extends IntegrationTestSupport {

  private static final long GUARDIAN_ID = 9410L;
  private static final long CHILD_ID = 9411L;
  private static final long TYPE_ID = 9412L;

  @Autowired private ReportGenerationRetryRepository retryRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void seed() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (?, 'GUARDIAN', 'retry-guardian', 'ACTIVE')",
        GUARDIAN_ID);
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (?, 'retry-child', '2020-01-01', 'PRESCHOOL', 'COMPLETED', 'ACTIVE')",
        CHILD_ID);
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, is_active, display_order) "
            + "VALUES (?, 'RETRY_TEST', 'Retry Test', 'GENERAL', 'BOTH', TRUE, 1)",
        TYPE_ID);
  }

  @Test
  void adoptsOnlyRetryableFailuresAndClaimsThemOnce() {
    long retryable = seedReport(1L, "FAILED_RETRYABLE");
    seedReport(2L, "FAILED_FINAL");
    seedReport(3L, "FAILED");
    seedReport(4L, "GENERATING");

    assertThat(retryRepository.adopt(10)).isEqualTo(1);

    List<ReportGenerationRetry> claimed =
        retryRepository.claim(10, Duration.ofMinutes(5), 3);
    assertThat(claimed).hasSize(1);
    assertThat(claimed.get(0).reportId()).isEqualTo(retryable);
    assertThat(claimed.get(0).attemptCount()).isEqualTo(1);

    // 선점한 작업은 next_attempt_at 이 밀려 있어 곧바로 다시 집히지 않는다.
    //   이게 깨지면 두 파드가 같은 리포트를 동시에 다시 만든다.
    assertThat(retryRepository.claim(10, Duration.ofMinutes(5), 3)).isEmpty();
  }

  @Test
  void doesNotAdoptTheSameReportTwice() {
    seedReport(5L, "FAILED_RETRYABLE");

    assertThat(retryRepository.adopt(10)).isEqualTo(1);
    assertThat(retryRepository.adopt(10)).isZero();
  }

  @Test
  void abandonsExhaustedRetriesAsFinalFailure() {
    long reportId = seedReport(6L, "FAILED_RETRYABLE");
    retryRepository.adopt(10);
    for (int attempt = 0; attempt < 3; attempt++) {
      jdbcTemplate.update(
          "UPDATE report_generation_retries SET attempt_count = attempt_count + 1, "
              + "next_attempt_at = UTC_TIMESTAMP(6) WHERE report_id = ?",
          reportId);
    }

    assertThat(retryRepository.abandonExhausted(3)).isEqualTo(1);

    assertThat(reportStatusOf(reportId)).isEqualTo("FAILED_FINAL");
    assertThat(retryRepository.claim(10, Duration.ofMinutes(5), 3)).isEmpty();
    // 포기해도 행은 남는다 — 몇 번 만에 포기했는지가 다음에 이 자리를 볼 사람에게 필요하다.
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM report_generation_retries WHERE report_id = ?",
                Integer.class,
                reportId))
        .isEqualTo(1);
  }

  @Test
  void stopsClaimingOnceReportLeavesRetryableState() {
    long reportId = seedReport(7L, "FAILED_RETRYABLE");
    retryRepository.adopt(10);
    jdbcTemplate.update(
        "UPDATE reports SET report_status = 'COMPLETED' WHERE id = ?", reportId);

    assertThat(retryRepository.claim(10, Duration.ofMinutes(5), 3)).isEmpty();
  }

  private String reportStatusOf(long reportId) {
    return jdbcTemplate.queryForObject(
        "SELECT report_status FROM reports WHERE id = ?", String.class, reportId);
  }

  private long seedReport(long offset, String status) {
    long sessionId = 94000L + offset;
    long analysisId = 95000L + offset;
    long reportId = 96000L + offset;
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, input_method, session_status, current_stage, "
            + "started_at, completed_at) "
            + "VALUES (?, ?, ?, 'CANVAS', 'COMPLETED', 'COMPLETED', UTC_TIMESTAMP(6), "
            + "UTC_TIMESTAMP(6))",
        sessionId,
        CHILD_ID,
        TYPE_ID);
    jdbcTemplate.update(
        "INSERT INTO analyses "
            + "(id, drawing_session_id, analysis_type, analysis_task_type, analysis_status, "
            + "idempotency_key, requested_at) "
            + "VALUES (?, ?, 'FINAL', 'ACTIVITY_REPORT', 'FAILED', ?, UTC_TIMESTAMP(6))",
        analysisId,
        sessionId,
        "retry-key-" + offset);
    jdbcTemplate.update(
        "INSERT INTO reports "
            + "(id, drawing_session_id, analysis_id, report_version, report_status, "
            + "limitations_text, failure_reason, created_at, updated_at) "
            + "VALUES (?, ?, ?, 1, ?, '리포트를 만들지 못했습니다.', 'TIMEOUT', "
            + "UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))",
        reportId,
        sessionId,
        analysisId,
        status);
    return reportId;
  }
}
