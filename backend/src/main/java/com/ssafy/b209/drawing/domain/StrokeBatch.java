package com.ssafy.b209.drawing.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/** 한 그림 활동에서 연속 수신한 캔버스 이벤트와 행동 지표를 묶어 보존한다. */
@Entity
@Table(
    name = "stroke_batches",
    uniqueConstraints =
        @UniqueConstraint(
            name = "uk_stroke_batches_session_sequence",
            columnNames = {"drawing_session_id", "batch_sequence"}))
public class StrokeBatch {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_session_id", nullable = false)
  private DrawingSession drawingSession;

  @Column(name = "batch_sequence", nullable = false)
  private int batchSequence;

  @Column(name = "first_event_sequence", nullable = false)
  private long firstEventSequence;

  @Column(name = "last_event_sequence", nullable = false)
  private long lastEventSequence;

  @Column(name = "event_count", nullable = false)
  private int eventCount;

  @Column(name = "payload_checksum_sha256", nullable = false, columnDefinition = "CHAR(64)")
  private String payloadChecksumSha256;

  @Column(name = "undo_count_delta", nullable = false)
  private int undoCountDelta;

  @Column(name = "redo_count_delta", nullable = false)
  private int redoCountDelta;

  @Column(name = "erase_count_delta", nullable = false)
  private int eraseCountDelta;

  @Column(name = "pause_duration_ms_delta", nullable = false)
  private long pauseDurationMsDelta;

  @Column(name = "client_created_at")
  private LocalDateTime clientCreatedAt;

  @Column(name = "received_at", nullable = false)
  private LocalDateTime receivedAt;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @OneToMany(mappedBy = "strokeBatch", cascade = CascadeType.ALL, orphanRemoval = true)
  private List<StrokeEvent> events = new ArrayList<>();

  /** JPA가 Stroke 배치를 복원할 때 사용한다. */
  protected StrokeBatch() {}

  /**
   * 검증된 요청 값으로 새 Stroke 배치를 만든다.
   *
   * @param drawingSession 배치가 속한 그림 활동
   * @param batchSequence 세션 내 배치 순번
   * @param firstEventSequence 첫 이벤트 순번
   * @param lastEventSequence 마지막 이벤트 순번
   * @param payloadChecksumSha256 요청 payload의 SHA-256
   * @param undoCountDelta 실행 취소 증가량
   * @param redoCountDelta 다시 실행 증가량
   * @param eraseCountDelta 지우기 증가량
   * @param pauseDurationMsDelta 일시 정지 시간 증가량
   * @param clientCreatedAt 클라이언트 생성 시각
   * @param receivedAt 서버 수신 시각
   * @return 이벤트를 추가할 수 있는 새 배치
   */
  public static StrokeBatch create(
      DrawingSession drawingSession,
      int batchSequence,
      long firstEventSequence,
      long lastEventSequence,
      String payloadChecksumSha256,
      int undoCountDelta,
      int redoCountDelta,
      int eraseCountDelta,
      long pauseDurationMsDelta,
      LocalDateTime clientCreatedAt,
      LocalDateTime receivedAt) {
    StrokeBatch batch = new StrokeBatch();
    batch.drawingSession = Objects.requireNonNull(drawingSession);
    batch.batchSequence = batchSequence;
    batch.firstEventSequence = firstEventSequence;
    batch.lastEventSequence = lastEventSequence;
    batch.payloadChecksumSha256 = Objects.requireNonNull(payloadChecksumSha256);
    batch.undoCountDelta = undoCountDelta;
    batch.redoCountDelta = redoCountDelta;
    batch.eraseCountDelta = eraseCountDelta;
    batch.pauseDurationMsDelta = pauseDurationMsDelta;
    batch.clientCreatedAt = Objects.requireNonNull(clientCreatedAt);
    batch.receivedAt = Objects.requireNonNull(receivedAt);
    batch.createdAt = receivedAt;
    return batch;
  }

  /**
   * 배치에 순서가 검증된 이벤트를 추가한다.
   *
   * @param event 추가할 이벤트
   */
  public void addEvent(StrokeEvent event) {
    events.add(Objects.requireNonNull(event));
    event.attachTo(this);
    eventCount = events.size();
  }

  /**
   * 저장된 배치 식별자를 반환한다.
   *
   * @return 배치 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * 세션 내 배치 순번을 반환한다.
   *
   * @return 배치 순번
   */
  public int getBatchSequence() {
    return batchSequence;
  }

  /**
   * 배치의 마지막 이벤트 순번을 반환한다.
   *
   * @return 마지막 이벤트 순번
   */
  public long getLastEventSequence() {
    return lastEventSequence;
  }

  /**
   * 저장된 이벤트 수를 반환한다.
   *
   * @return 이벤트 수
   */
  public int getEventCount() {
    return eventCount;
  }

  /**
   * 멱등 비교에 사용하는 payload SHA-256을 반환한다.
   *
   * @return 64자 소문자 Hex checksum
   */
  public String getPayloadChecksumSha256() {
    return payloadChecksumSha256;
  }

  /**
   * 서버가 배치를 수신한 시각을 반환한다.
   *
   * @return UTC 기준 수신 시각
   */
  public LocalDateTime getReceivedAt() {
    return receivedAt;
  }
}
