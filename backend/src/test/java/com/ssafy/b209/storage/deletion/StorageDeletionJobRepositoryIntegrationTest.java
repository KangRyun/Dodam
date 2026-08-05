package com.ssafy.b209.storage.deletion;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * {@link StorageDeletionJobRepository} 를 실 MySQL 로 검증한다 (S15P11B209-780).
 *
 * <p>단위 테스트로는 못 잡는 것을 본다: {@code for update skip locked} 문법, {@code date_sub(... interval ?
 * second)} 바인딩, CHECK 제약(deletion_status 4종), {@code error_code} VARCHAR(80) 길이. 이 SQL 들이 깨지면 워커가
 * 조용히 아무것도 못 지운다.
 */
@Testcontainers
@SpringBootTest
@ActiveProfiles("integration-test")
class StorageDeletionJobRepositoryIntegrationTest {

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_storage_deletion")
          .withUsername("test")
          .withPassword("test");

  @Autowired private StorageDeletionJobRepository repository;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    jdbcTemplate.update("delete from storage_deletion_jobs");
  }

  private long insertPending(String storageKey, String resourceType) {
    jdbcTemplate.update(
        """
        insert into storage_deletion_jobs (storage_key, resource_type, resource_id)
        values (?, ?, null)
        """,
        storageKey,
        resourceType);
    return jdbcTemplate.queryForObject("select last_insert_id()", Long.class);
  }

  private Map<String, Object> row(long id) {
    return jdbcTemplate.queryForMap("select * from storage_deletion_jobs where id = ?", id);
  }

  @Test
  @DisplayName("claim 은 PENDING 을 PROCESSING 으로 선점하고 그 목록을 돌려준다")
  void claimMarksProcessingAndReturnsJobs() {
    long id = insertPending("2026/08/a.png", "DRAWING_ASSET");

    List<StorageDeletionJob> claimed = repository.claim(10);

    assertThat(claimed).hasSize(1);
    assertThat(claimed.get(0).id()).isEqualTo(id);
    assertThat(claimed.get(0).storageKey()).isEqualTo("2026/08/a.png");
    assertThat(claimed.get(0).resourceType()).isEqualTo("DRAWING_ASSET");
    assertThat(row(id))
        .containsEntry("deletion_status", "PROCESSING")
        .hasEntrySatisfying("last_attempted_at", value -> assertThat(value).isNotNull());
  }

  @Test
  @DisplayName("claim 은 배치 크기를 넘지 않고 오래된 것부터 집는다")
  void claimRespectsBatchSizeAndOrder() {
    long first = insertPending("2026/08/first.png", "DRAWING_ASSET");
    insertPending("2026/08/second.png", "DRAWING_ASSET");
    insertPending("2026/08/third.png", "DRAWING_ASSET");

    List<StorageDeletionJob> claimed = repository.claim(2);

    assertThat(claimed).hasSize(2);
    assertThat(claimed.get(0).id()).isEqualTo(first);
  }

  @Test
  @DisplayName("이미 선점된 잡은 다시 집지 않는다")
  void claimSkipsAlreadyProcessing() {
    insertPending("2026/08/a.png", "DRAWING_ASSET");
    repository.claim(10);

    assertThat(repository.claim(10)).isEmpty();
  }

  @Test
  @DisplayName("markCompleted 는 완료 시각을 남기고 오류 코드를 지운다")
  void markCompletedSetsCompletedAt() {
    long id = insertPending("2026/08/a.png", "DRAWING_ASSET");
    repository.claim(10);
    repository.markRetry(id, "Boom");

    repository.markCompleted(id);

    assertThat(row(id))
        .containsEntry("deletion_status", "COMPLETED")
        .containsEntry("error_code", null)
        .hasEntrySatisfying("completed_at", value -> assertThat(value).isNotNull());
  }

  @Test
  @DisplayName("markRetry 는 PENDING 으로 되돌리고 재시도 횟수를 올린다")
  void markRetryReturnsToPending() {
    long id = insertPending("2026/08/a.png", "DRAWING_ASSET");
    repository.claim(10);

    repository.markRetry(id, "SdkException");

    assertThat(row(id))
        .containsEntry("deletion_status", "PENDING")
        .containsEntry("retry_count", 1)
        .containsEntry("error_code", "SdkException");
    // 되돌아갔으니 다음 실행에서 다시 집혀야 한다.
    assertThat(repository.claim(10)).hasSize(1);
  }

  @Test
  @DisplayName("markFailed 는 행을 남긴다 — 무엇이 안 지워졌는지의 유일한 기록")
  void markFailedKeepsRow() {
    long id = insertPending("2026/08/a.png", "REPORT_PDF");
    repository.claim(10);

    repository.markFailed(id, StorageDeletionRouter.UNMAPPED_RESOURCE_TYPE);

    assertThat(row(id))
        .containsEntry("deletion_status", "FAILED")
        .containsEntry("error_code", StorageDeletionRouter.UNMAPPED_RESOURCE_TYPE);
    // FAILED 는 다시 집지 않는다 — 사람이 봐야 하는 상태다.
    assertThat(repository.claim(10)).isEmpty();
  }

  @Test
  @DisplayName("error_code 는 컬럼 길이(80)를 넘겨도 UPDATE 가 깨지지 않는다")
  void truncatesLongErrorCode() {
    long id = insertPending("2026/08/a.png", "DRAWING_ASSET");
    repository.claim(10);

    repository.markRetry(id, "E".repeat(200));

    assertThat((String) row(id).get("error_code")).hasSize(80);
  }

  @Test
  @DisplayName("releaseStuck 은 오래 선점된 잡만 PENDING 으로 회수한다")
  void releaseStuckRecoversOnlyOldProcessing() {
    long stuck = insertPending("2026/08/stuck.png", "DRAWING_ASSET");
    long fresh = insertPending("2026/08/fresh.png", "DRAWING_ASSET");
    repository.claim(10);
    // 죽은 파드가 20분 전에 집어간 상황을 만든다.
    jdbcTemplate.update(
        "update storage_deletion_jobs set last_attempted_at = date_sub(current_timestamp(6), interval 20 minute) where id = ?",
        stuck);

    int released = repository.releaseStuck(600L);

    assertThat(released).isEqualTo(1);
    assertThat(row(stuck)).containsEntry("deletion_status", "PENDING");
    assertThat(row(fresh)).containsEntry("deletion_status", "PROCESSING");
  }

  @Test
  @DisplayName("배치 크기가 0 이하면 DB 를 건드리지 않는다")
  void claimWithNonPositiveBatchSizeDoesNothing() {
    insertPending("2026/08/a.png", "DRAWING_ASSET");

    assertThat(repository.claim(0)).isEmpty();
    assertThat(
            jdbcTemplate.queryForObject(
                "select deletion_status from storage_deletion_jobs", String.class))
        .isEqualTo("PENDING");
  }
}
