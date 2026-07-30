package com.ssafy.b209.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.drawing.config.StrokeMongoBackfillProperties;
import com.ssafy.b209.drawing.config.StrokeRetentionProperties;
import com.ssafy.b209.drawing.document.StrokeBatchDocument;
import com.ssafy.b209.drawing.document.StrokeEventDocument;
import com.ssafy.b209.drawing.document.StrokePointDocument;
import com.ssafy.b209.drawing.repository.StrokeBatchDocumentRepository;
import com.ssafy.b209.drawing.repository.StrokeBatchIdSequenceRepository;
import com.ssafy.b209.drawing.service.StrokeMongoBackfillRunner;
import com.ssafy.b209.support.IntegrationTestSupport;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Stroke 저장소를 MongoDB로 옮긴 뒤의 저장·삭제·이관 동작을 실제 컨테이너로 검증한다 (S15P11B209-365).
 *
 * <p>Mock 으로는 검증할 수 없는 것들만 여기서 다룬다 — unique 인덱스가 실제로 중복을 막는지, {@code deleteMany} 가 다른 아동 데이터를 건드리지
 * 않는지, MySQL 의 KST 벽시계가 이관 후에도 같은 순간을 가리키는지.
 */
class StrokeMongoIntegrationTest extends IntegrationTestSupport {

  private static final ZoneId KST = ZoneId.of("Asia/Seoul");
  private static final int RETENTION_DAYS = 180;

  @Autowired private StrokeBatchDocumentRepository strokeBatchDocumentRepository;
  @Autowired private StrokeBatchIdSequenceRepository strokeBatchIdSequenceRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void seedRelationalFixtures() {
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) "
            + "VALUES (41, 'GUARDIAN', 'stroke-guardian', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO children "
            + "(id, nickname, birth_date, question_difficulty, tutorial_status, profile_status) "
            + "VALUES (1, 'child-one', '2020-07-21', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE'), "
            + "(2, 'child-two', '2019-07-21', 'PRESCHOOL', 'NOT_STARTED', 'ACTIVE')");
    jdbcTemplate.update(
        "INSERT INTO drawing_types "
            + "(id, code, name, activity_category, selectable_by, recommended_age_min, "
            + "recommended_age_max, is_active, display_order) "
            + "VALUES (1, 'FREE_DRAWING', 'Free Drawing', 'GENERAL', 'BOTH', 3, 12, TRUE, 1)");
  }

  @Test
  void theUniqueIndexRejectsASecondBatchWithTheSameSessionAndSequence() {
    // 앱의 선조회는 동시 요청을 막지 못한다. 최종 방어선이 실제로 서 있는지 확인한다.
    strokeBatchDocumentRepository.insert(document(1L, 7L, 1, "checksum-a"));

    assertThatThrownBy(
            () -> strokeBatchDocumentRepository.insert(document(2L, 7L, 1, "checksum-b")))
        .isInstanceOf(DuplicateKeyException.class);
  }

  @Test
  void deletingByChildRemovesOnlyThatChildsBatches() {
    strokeBatchDocumentRepository.insert(document(1L, 7L, 1, "checksum-a", 1L));
    strokeBatchDocumentRepository.insert(document(2L, 7L, 2, "checksum-b", 1L));
    strokeBatchDocumentRepository.insert(document(3L, 8L, 1, "checksum-c", 2L));

    long deleted = strokeBatchDocumentRepository.deleteByChildId(1L);

    assertThat(deleted).isEqualTo(2);
    assertThat(strokeBatchDocumentRepository.count()).isEqualTo(1);
    assertThat(strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(8L, 1))
        .isPresent()
        .get()
        .extracting(StrokeBatchDocument::childId)
        .isEqualTo(2L);
  }

  @Test
  void deletingBySessionRemovesEveryBatchOfThatSession() {
    strokeBatchDocumentRepository.insert(document(1L, 7L, 1, "checksum-a"));
    strokeBatchDocumentRepository.insert(document(2L, 7L, 2, "checksum-b"));
    strokeBatchDocumentRepository.insert(document(3L, 9L, 1, "checksum-c"));

    long deleted = strokeBatchDocumentRepository.deleteBySessionId(7L);

    assertThat(deleted).isEqualTo(2);
    assertThat(strokeBatchDocumentRepository.count()).isEqualTo(1);
  }

  @Test
  void issuesMonotonicNumericIdsAcrossConcurrentCallers() {
    long first = strokeBatchIdSequenceRepository.next();
    long second = strokeBatchIdSequenceRepository.next();

    assertThat(first).isEqualTo(1L);
    assertThat(second).isEqualTo(2L);
  }

  @Test
  void backfillReadsMysqlWallClockAsKstSoTheInstantDoesNotShiftByNineHours() {
    // ⚠️ 이 테스트가 이 작업의 핵심 회귀 방지선이다.
    //   MySQL DATETIME 은 KST 벽시계다(V26 / S15P11B209-736). UTC 로 해석하면 전 데이터가 9시간 밀리고,
    //   밀린 값은 눈으로 구분되지 않는다 — expireAt 까지 함께 밀려 보관 기간이 어긋난다.
    LocalDateTime mysqlWallClock = LocalDateTime.of(2026, 7, 21, 11, 32, 10);
    seedMysqlStrokeBatch(mysqlWallClock);

    runner().run(null);

    StrokeBatchDocument migrated =
        strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(1L, 3).orElseThrow();
    Instant expected = mysqlWallClock.atZone(KST).toInstant();
    assertThat(migrated.receivedAt()).isEqualTo(expected);
    assertThat(migrated.createdAt()).isEqualTo(expected);
    // 2026-07-21T11:32:10 KST == 2026-07-21T02:32:10Z. UTC 로 해석했다면 11:32:10Z 가 됐을 것이다.
    assertThat(migrated.receivedAt()).isEqualTo(Instant.parse("2026-07-21T02:32:10Z"));
    assertThat(migrated.expireAt()).isEqualTo(expected.plus(RETENTION_DAYS, ChronoUnit.DAYS));
  }

  @Test
  void backfillCarriesEventsAndPointsAndIsIdempotent() {
    seedMysqlStrokeBatch(LocalDateTime.of(2026, 7, 21, 11, 32, 10));

    runner().run(null);
    runner().run(null);

    assertThat(strokeBatchDocumentRepository.count()).isEqualTo(1);
    StrokeBatchDocument migrated =
        strokeBatchDocumentRepository.findBySessionIdAndBatchSeq(1L, 3).orElseThrow();
    assertThat(migrated.childId()).isEqualTo(1L);
    assertThat(migrated.eventCount()).isEqualTo(1);
    assertThat(migrated.pointCount()).isEqualTo(2);
    assertThat(migrated.strokes())
        .singleElement()
        .satisfies(
            event -> {
              assertThat(event.strokeSeq()).isEqualTo(101L);
              assertThat(event.eventType()).isEqualTo("STROKE");
              assertThat(event.tool()).isEqualTo("PEN");
              assertThat(event.points()).hasSize(2);
              assertThat(event.points().getFirst().elapsedMs()).isZero();
              assertThat(event.points().getLast().elapsedMs()).isEqualTo(16L);
            });
  }

  @Test
  void backfillSkipsSessionsThatWereAlreadyDeleted() {
    // 삭제된 세션의 데이터를 다시 되살리면 안 된다 — 이관이 가드레일을 되돌리는 셈이 된다.
    seedMysqlStrokeBatch(LocalDateTime.of(2026, 7, 21, 11, 32, 10));
    jdbcTemplate.update(
        "UPDATE drawing_sessions SET deleted_at = ?, session_status = 'DELETED' WHERE id = 1",
        LocalDateTime.of(2026, 7, 22, 9, 0));

    runner().run(null);

    assertThat(strokeBatchDocumentRepository.count()).isZero();
  }

  @Test
  void backfillSkipsChildrenThatWereAlreadyDeleted() {
    // MySQL 은 Soft Delete 라 삭제된 아동의 stroke_* 행이 남아 있다. 이관이 그걸 되살리면
    //   "탈퇴 시 아동 데이터 삭제"(가드레일 9절)가 조용히 무효가 된다.
    seedMysqlStrokeBatch(LocalDateTime.of(2026, 7, 21, 11, 32, 10));
    jdbcTemplate.update(
        "UPDATE children SET profile_status = 'DELETED', deleted_at = ? WHERE id = 1",
        LocalDateTime.of(2026, 7, 22, 9, 0));

    runner().run(null);

    assertThat(strokeBatchDocumentRepository.count()).isZero();
  }

  private StrokeMongoBackfillRunner runner() {
    // ApplicationRunner 는 Context 기동 시점에 도는데, 그때는 아직 시드 데이터가 없다.
    //   러너 자체는 상태가 없으므로 직접 만들어 호출하는 편이 검증 대상을 정확히 겨눈다.
    return new StrokeMongoBackfillRunner(
        jdbcTemplate,
        strokeBatchDocumentRepository,
        strokeBatchIdSequenceRepository,
        new StrokeRetentionProperties(RETENTION_DAYS),
        new StrokeMongoBackfillProperties(true, 200));
  }

  private void seedMysqlStrokeBatch(LocalDateTime wallClock) {
    jdbcTemplate.update(
        "INSERT INTO drawing_sessions "
            + "(id, child_id, drawing_type_id, started_by_user_id, input_method, session_status, "
            + "current_stage, started_at, idempotency_key) "
            + "VALUES (1, 1, 1, 41, 'CANVAS', 'IN_PROGRESS', 'DRAWING', ?, 'backfill-seed')",
        wallClock);
    jdbcTemplate.update(
        "INSERT INTO stroke_batches "
            + "(id, drawing_session_id, batch_sequence, first_event_sequence, last_event_sequence, "
            + "event_count, payload_checksum_sha256, undo_count_delta, redo_count_delta, "
            + "erase_count_delta, pause_duration_ms_delta, client_created_at, received_at, created_at) "
            + "VALUES (1, 1, 3, 101, 101, 1, ?, 1, 0, 2, 3200, ?, ?, ?)",
        "a".repeat(64),
        wallClock,
        wallClock,
        wallClock);
    jdbcTemplate.update(
        "INSERT INTO stroke_events "
            + "(id, stroke_batch_id, event_sequence, event_type, tool, color, width, pressure, created_at) "
            + "VALUES (1, 1, 101, 'STROKE', 'PEN', '#FFCC00', 8.000, NULL, ?)",
        wallClock);
    jdbcTemplate.update(
        "INSERT INTO stroke_event_points "
            + "(stroke_event_id, point_sequence, x, y, elapsed_ms, pressure) "
            + "VALUES (1, 0, 0.180000, 0.420000, 0, NULL), "
            + "(1, 1, 0.190000, 0.430000, 16, NULL)");
  }

  private StrokeBatchDocument document(long id, long sessionId, int batchSeq, String checksum) {
    return document(id, sessionId, batchSeq, checksum, 1L);
  }

  private StrokeBatchDocument document(
      long id, long sessionId, int batchSeq, String checksum, Long childId) {
    Instant now = Instant.parse("2026-07-21T02:32:10Z");
    return new StrokeBatchDocument(
        id,
        sessionId,
        childId,
        batchSeq,
        101,
        101,
        1,
        1,
        checksum,
        0,
        0,
        0,
        0,
        now,
        now,
        now,
        now.plus(RETENTION_DAYS, ChronoUnit.DAYS),
        List.of(
            new StrokeEventDocument(
                101,
                "STROKE",
                "PEN",
                "#FFCC00",
                BigDecimal.valueOf(8),
                null,
                List.of(
                    new StrokePointDocument(
                        BigDecimal.valueOf(0.18), BigDecimal.valueOf(0.42), 0, null)))));
  }
}
