package com.ssafy.b209.drawing.service;

import com.ssafy.b209.drawing.config.StrokeMongoBackfillProperties;
import com.ssafy.b209.drawing.config.StrokeRetentionProperties;
import com.ssafy.b209.drawing.document.StrokeBatchDocument;
import com.ssafy.b209.drawing.document.StrokeEventDocument;
import com.ssafy.b209.drawing.document.StrokePointDocument;
import com.ssafy.b209.drawing.repository.StrokeBatchDocumentRepository;
import com.ssafy.b209.drawing.repository.StrokeBatchIdSequenceRepository;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * MySQL {@code stroke_*} 테이블에 남은 그리기 과정 데이터를 MongoDB로 옮기는 일회성 러너다 (S15P11B209-365).
 *
 * <p><b>기본은 비활성이다.</b> {@code STROKE_MONGO_BACKFILL=true} 로 켰을 때만 Bean 이 만들어진다. 플래그가 없으면 이 클래스는 아예
 * 존재하지 않는 것과 같다.
 *
 * <p><b>⚠️ 시각 변환이 이 작업의 핵심이다.</b> MySQL 의 {@code DATETIME} 값은 <b>KST 벽시계</b>다 (S15P11B209-736 / V26
 * 이후, {@code docs/인프라/DB접속.md} 1-b절). JDBC 가 돌려주는 {@link LocalDateTime} 에는 시간대가 없으므로, 이것을 UTC 로
 * 해석하면 <b>전 데이터가 9시간 밀린다.</b> 반드시 {@code Asia/Seoul} 로 해석해 {@link Instant} 로 바꾼다. 밀린 값은 눈으로 구분되지
 * 않고, {@code expireAt} 까지 함께 밀려 보관 기간이 어긋난다.
 *
 * <p><b>멱등하다.</b> {@code (sessionId, batchSeq)} 로 이미 있는 문서는 건너뛴다. 중간에 죽어도 다시 돌리면 이어서 진행한다.
 *
 * <p><b>⚠️ 삭제된 세션·아동은 옮기지 않는다.</b> MySQL 은 Soft Delete 라 삭제된 아동의 {@code stroke_*} 행이 그대로 남아 있다. 필터가
 * 없으면 이 러너가 <b>이미 지운 아동의 그리기 기록을 Mongo 로 되살린다</b> — 이관이 가드레일(CLAUDE.md 9절)을 되돌리는 셈이 된다. 삭제 경로는 Mongo
 * 문서를 즉시 지우도록 되어 있으므로(StrokeBatchDeletionService) 여기서 다시 넣으면 그 조치가 무의미해진다.
 */
@Component
@ConditionalOnProperty(name = "app.stroke.mongo-backfill.enabled", havingValue = "true")
public class StrokeMongoBackfillRunner implements ApplicationRunner {

  private static final Logger log = LoggerFactory.getLogger(StrokeMongoBackfillRunner.class);

  /** MySQL DATETIME 값을 해석할 시간대. 저장 규약이 KST 이므로 바꾸면 안 된다. */
  private static final ZoneId MYSQL_ZONE = ZoneId.of("Asia/Seoul");

  private static final String SELECT_BATCHES =
      """
      select batch.id,
             batch.drawing_session_id,
             session.child_id,
             batch.batch_sequence,
             batch.first_event_sequence,
             batch.last_event_sequence,
             batch.event_count,
             batch.payload_checksum_sha256,
             batch.undo_count_delta,
             batch.redo_count_delta,
             batch.erase_count_delta,
             batch.pause_duration_ms_delta,
             batch.client_created_at,
             batch.received_at,
             batch.created_at
        from stroke_batches batch
        join drawing_sessions session on session.id = batch.drawing_session_id
        join children child on child.id = session.child_id
       where batch.id > ?
         and session.deleted_at is null
         and child.deleted_at is null
         and child.profile_status <> 'DELETED'
       order by batch.id
       limit ?
      """;

  private static final String SELECT_EVENTS =
      """
      select id, event_sequence, event_type, tool, color, width, pressure
        from stroke_events
       where stroke_batch_id = ?
       order by event_sequence
      """;

  private static final String SELECT_POINTS =
      """
      select x, y, elapsed_ms, pressure
        from stroke_event_points
       where stroke_event_id = ?
       order by point_sequence
      """;

  private final JdbcTemplate jdbcTemplate;
  private final StrokeBatchDocumentRepository strokeBatchDocumentRepository;
  private final StrokeBatchIdSequenceRepository strokeBatchIdSequenceRepository;
  private final StrokeRetentionProperties retentionProperties;
  private final StrokeMongoBackfillProperties backfillProperties;

  /**
   * 이관에 필요한 원본·대상 저장소와 보관 정책을 주입한다.
   *
   * @param jdbcTemplate MySQL 원본 조회 도구
   * @param strokeBatchDocumentRepository MongoDB 대상 Repository
   * @param strokeBatchIdSequenceRepository 배치 식별자 발급 Repository
   * @param retentionProperties 보관 기간 설정
   * @param backfillProperties 이관 페이지 크기 설정
   */
  public StrokeMongoBackfillRunner(
      JdbcTemplate jdbcTemplate,
      StrokeBatchDocumentRepository strokeBatchDocumentRepository,
      StrokeBatchIdSequenceRepository strokeBatchIdSequenceRepository,
      StrokeRetentionProperties retentionProperties,
      StrokeMongoBackfillProperties backfillProperties) {
    this.jdbcTemplate = jdbcTemplate;
    this.strokeBatchDocumentRepository = strokeBatchDocumentRepository;
    this.strokeBatchIdSequenceRepository = strokeBatchIdSequenceRepository;
    this.retentionProperties = retentionProperties;
    this.backfillProperties = backfillProperties;
  }

  /**
   * MySQL 배치를 순서대로 읽어 MongoDB에 이관한다.
   *
   * @param args 애플리케이션 기동 인자. 사용하지 않는다
   */
  @Override
  public void run(ApplicationArguments args) {
    log.info("Stroke MongoDB 이관을 시작합니다. batchSize={}", backfillProperties.batchSize());
    long lastId = 0;
    int migrated = 0;
    int skipped = 0;
    Instant firstSampleSource = null;
    Instant firstSampleStored = null;
    while (true) {
      List<Map<String, Object>> rows =
          jdbcTemplate.queryForList(SELECT_BATCHES, lastId, backfillProperties.batchSize());
      if (rows.isEmpty()) {
        break;
      }
      for (Map<String, Object> row : rows) {
        lastId = ((Number) row.get("id")).longValue();
        long sessionId = ((Number) row.get("drawing_session_id")).longValue();
        int batchSeq = ((Number) row.get("batch_sequence")).intValue();
        if (strokeBatchDocumentRepository
            .findBySessionIdAndBatchSeq(sessionId, batchSeq)
            .isPresent()) {
          skipped++;
          continue;
        }
        StrokeBatchDocument document = toDocument(row, lastId, sessionId, batchSeq);
        strokeBatchDocumentRepository.insert(document);
        migrated++;
        if (firstSampleSource == null) {
          firstSampleSource = toInstant(row.get("received_at"));
          firstSampleStored = document.receivedAt();
        }
      }
    }
    log.info(
        "Stroke MongoDB 이관을 마쳤습니다. migrated={}, skipped={}, lastSourceId={}",
        migrated,
        skipped,
        lastId);
    if (firstSampleSource != null) {
      // 시각 변환 검증용 표본. 두 값이 같아야 하고, UTC 로 잘못 해석했다면 9시간 차이로 드러난다.
      log.info(
          "시각 변환 표본 대조: mysqlReceivedAt(KST 해석)={}, mongoReceivedAt={}, zone={}",
          firstSampleSource,
          firstSampleStored,
          MYSQL_ZONE);
    }
  }

  private StrokeBatchDocument toDocument(
      Map<String, Object> row, long sourceBatchId, long sessionId, int batchSeq) {
    Instant createdAt = toInstant(row.get("created_at"));
    List<StrokeEventDocument> events = readEvents(sourceBatchId);
    int pointCount = events.stream().mapToInt(event -> event.points().size()).sum();
    return new StrokeBatchDocument(
        strokeBatchIdSequenceRepository.next(),
        sessionId,
        ((Number) row.get("child_id")).longValue(),
        batchSeq,
        ((Number) row.get("first_event_sequence")).longValue(),
        ((Number) row.get("last_event_sequence")).longValue(),
        ((Number) row.get("event_count")).intValue(),
        pointCount,
        (String) row.get("payload_checksum_sha256"),
        ((Number) row.get("undo_count_delta")).intValue(),
        ((Number) row.get("redo_count_delta")).intValue(),
        ((Number) row.get("erase_count_delta")).intValue(),
        ((Number) row.get("pause_duration_ms_delta")).longValue(),
        toInstant(row.get("client_created_at")),
        toInstant(row.get("received_at")),
        createdAt,
        createdAt.plus(retentionProperties.retention()),
        events);
  }

  private List<StrokeEventDocument> readEvents(long sourceBatchId) {
    List<Map<String, Object>> eventRows = jdbcTemplate.queryForList(SELECT_EVENTS, sourceBatchId);
    List<StrokeEventDocument> events = new ArrayList<>(eventRows.size());
    for (Map<String, Object> eventRow : eventRows) {
      long eventId = ((Number) eventRow.get("id")).longValue();
      events.add(
          new StrokeEventDocument(
              ((Number) eventRow.get("event_sequence")).longValue(),
              (String) eventRow.get("event_type"),
              (String) eventRow.get("tool"),
              (String) eventRow.get("color"),
              (BigDecimal) eventRow.get("width"),
              (BigDecimal) eventRow.get("pressure"),
              readPoints(eventId)));
    }
    return List.copyOf(events);
  }

  private List<StrokePointDocument> readPoints(long eventId) {
    List<Map<String, Object>> pointRows = jdbcTemplate.queryForList(SELECT_POINTS, eventId);
    List<StrokePointDocument> points = new ArrayList<>(pointRows.size());
    for (Map<String, Object> pointRow : pointRows) {
      points.add(
          new StrokePointDocument(
              (BigDecimal) pointRow.get("x"),
              (BigDecimal) pointRow.get("y"),
              ((Number) pointRow.get("elapsed_ms")).longValue(),
              (BigDecimal) pointRow.get("pressure")));
    }
    return List.copyOf(points);
  }

  /**
   * MySQL DATETIME 값을 KST 벽시계로 해석해 {@link Instant} 로 바꾼다.
   *
   * @param value JDBC가 돌려준 시각 값. {@code null} 이면 {@code null}
   * @return UTC 기준 시각
   */
  static Instant toInstant(Object value) {
    if (value == null) {
      return null;
    }
    LocalDateTime localDateTime =
        switch (value) {
          case LocalDateTime dateTime -> dateTime;
          case Timestamp timestamp -> timestamp.toLocalDateTime();
          default ->
              throw new IllegalStateException(
                  "Unsupported MySQL datetime type: " + value.getClass().getName());
        };
    return localDateTime.atZone(MYSQL_ZONE).toInstant();
  }
}
