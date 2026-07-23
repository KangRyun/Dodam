package com.ssafy.b209.drawing.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.util.Objects;

/** Stroke 이벤트 내부의 정규화된 단일 좌표와 경과 시간을 보존한다. */
@Entity
@Table(name = "stroke_event_points")
public class StrokeEventPoint {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "stroke_event_id", nullable = false)
  private StrokeEvent strokeEvent;

  @Column(name = "point_sequence", nullable = false)
  private int pointSequence;

  @Column(nullable = false, precision = 8, scale = 6)
  private BigDecimal x;

  @Column(nullable = false, precision = 8, scale = 6)
  private BigDecimal y;

  @Column(name = "elapsed_ms", nullable = false)
  private long elapsedMs;

  @Column(precision = 6, scale = 5)
  private BigDecimal pressure;

  /** JPA가 Stroke 좌표를 복원할 때 사용한다. */
  protected StrokeEventPoint() {}

  /**
   * 이벤트 내부 순서와 정규화 좌표로 새 점을 만든다.
   *
   * @param pointSequence 이벤트 내부 좌표 순번
   * @param x 정규화 X 좌표
   * @param y 정규화 Y 좌표
   * @param elapsedMs 이벤트 시작 후 경과 시간
   * @param pressure 좌표별 필압
   * @return 새 좌표
   */
  public static StrokeEventPoint create(
      int pointSequence, BigDecimal x, BigDecimal y, long elapsedMs, BigDecimal pressure) {
    StrokeEventPoint point = new StrokeEventPoint();
    point.pointSequence = pointSequence;
    point.x = Objects.requireNonNull(x);
    point.y = Objects.requireNonNull(y);
    point.elapsedMs = elapsedMs;
    point.pressure = pressure;
    return point;
  }

  void attachTo(StrokeEvent event) {
    strokeEvent = Objects.requireNonNull(event);
  }
}
