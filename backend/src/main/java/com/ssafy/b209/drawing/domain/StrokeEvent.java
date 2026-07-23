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
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/** Stroke 배치 내부의 단일 그리기·편집 행위와 좌표 목록을 보존한다. */
@Entity
@Table(name = "stroke_events")
public class StrokeEvent {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "stroke_batch_id", nullable = false)
  private StrokeBatch strokeBatch;

  @Column(name = "event_sequence", nullable = false)
  private long eventSequence;

  @Column(name = "event_type", nullable = false, length = 30)
  private String eventType;

  @Column(length = 30)
  private String tool;

  @Column(length = 9, columnDefinition = "CHAR(9)")
  private String color;

  @Column(precision = 8, scale = 3)
  private BigDecimal width;

  @Column(precision = 6, scale = 5)
  private BigDecimal pressure;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @OneToMany(mappedBy = "strokeEvent", cascade = CascadeType.ALL, orphanRemoval = true)
  private List<StrokeEventPoint> points = new ArrayList<>();

  /** JPA가 Stroke 이벤트를 복원할 때 사용한다. */
  protected StrokeEvent() {}

  /**
   * 검증된 캔버스 이벤트를 생성한다.
   *
   * @param eventSequence 세션 전체 이벤트 순번
   * @param eventType 이벤트 유형
   * @param tool 도구
   * @param color Hex 색상
   * @param width 선 굵기
   * @param pressure 대표 필압
   * @param createdAt 서버 저장 시각
   * @return 좌표를 추가할 수 있는 새 이벤트
   */
  public static StrokeEvent create(
      long eventSequence,
      String eventType,
      String tool,
      String color,
      BigDecimal width,
      BigDecimal pressure,
      LocalDateTime createdAt) {
    StrokeEvent event = new StrokeEvent();
    event.eventSequence = eventSequence;
    event.eventType = Objects.requireNonNull(eventType);
    event.tool = tool;
    event.color = color;
    event.width = width;
    event.pressure = pressure;
    event.createdAt = Objects.requireNonNull(createdAt);
    return event;
  }

  void attachTo(StrokeBatch batch) {
    strokeBatch = Objects.requireNonNull(batch);
  }

  /**
   * 이벤트에 순서가 검증된 좌표를 추가한다.
   *
   * @param point 추가할 좌표
   */
  public void addPoint(StrokeEventPoint point) {
    points.add(Objects.requireNonNull(point));
    point.attachTo(this);
  }
}
