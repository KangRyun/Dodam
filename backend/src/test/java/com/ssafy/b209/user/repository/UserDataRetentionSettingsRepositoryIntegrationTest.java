package com.ssafy.b209.user.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.support.IntegrationTestSupport;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

class UserDataRetentionSettingsRepositoryIntegrationTest extends IntegrationTestSupport {

  private static final Long USER_ID = 51L;

  @Autowired private UserDataRetentionSettingsRepository repository;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private PlatformTransactionManager transactionManager;

  @BeforeEach
  void insertUser() {
    jdbcTemplate.update(
        "insert into users (id, role, nickname, account_status) "
            + "values (?, 'GUARDIAN', '보관정책사용자', 'ACTIVE')",
        USER_ID);
  }

  @Test
  void insertsSettingsWhenTheUserHasNoRow() {
    upsert(365, 14);

    assertThat(countRows()).isEqualTo(1);
    assertThat(readSettings()).isEqualTo(new Settings(365, 14));
  }

  @Test
  void updatesTheSingleExistingRowAndDoesNotInventAMaximum() {
    upsert(365, 14);
    upsert(Integer.MAX_VALUE, 0);

    assertThat(countRows()).isEqualTo(1);
    assertThat(readSettings()).isEqualTo(new Settings(Integer.MAX_VALUE, 0));
  }

  private void upsert(int retentionDays, int noticeDaysBefore) {
    new TransactionTemplate(transactionManager)
        .executeWithoutResult(
            status -> repository.upsert(USER_ID, retentionDays, noticeDaysBefore));
  }

  private Settings readSettings() {
    return new TransactionTemplate(transactionManager)
        .execute(
            status ->
                repository
                    .findByUserId(USER_ID)
                    .map(
                        projection ->
                            new Settings(
                                projection.getRetentionDays(), projection.getNoticeDaysBefore()))
                    .orElseThrow());
  }

  private int countRows() {
    return jdbcTemplate.queryForObject(
        "select count(*) from user_data_retention_settings where user_id = ?",
        Integer.class,
        USER_ID);
  }

  private record Settings(int retentionDays, int noticeDaysBefore) {}
}
