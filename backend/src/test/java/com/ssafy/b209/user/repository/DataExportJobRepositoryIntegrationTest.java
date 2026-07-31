package com.ssafy.b209.user.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.support.IntegrationTestSupport;
import com.ssafy.b209.user.domain.DataExportJob;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

class DataExportJobRepositoryIntegrationTest extends IntegrationTestSupport {

  private static final Long USER_ID = 51L;

  @Autowired private DataExportJobRepository repository;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void insertUser() {
    jdbcTemplate.update(
        "insert into users (id, role, nickname, account_status) "
            + "values (?, 'GUARDIAN', '내보내기사용자', 'ACTIVE')",
        USER_ID);
  }

  @Test
  void persistsThePendingJobUsingTheExistingDataExportJobsSchema() {
    LocalDateTime requestedAt = LocalDateTime.of(2026, 7, 31, 10, 25, 3);

    DataExportJob saved = repository.saveAndFlush(DataExportJob.requested(USER_ID, requestedAt));

    assertThat(saved.getId()).isNotNull();
    assertThat(
            jdbcTemplate.queryForMap(
                "select user_id, export_status, created_at from data_export_jobs where id = ?",
                saved.getId()))
        .containsEntry("user_id", USER_ID)
        .containsEntry("export_status", "PENDING")
        .containsEntry("created_at", requestedAt);
  }
}
