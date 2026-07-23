package com.ssafy.b209.analysis.domain;

import com.ssafy.b209.drawing.domain.DrawingAsset;
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
import java.time.LocalDateTime;
import java.util.Objects;

/** 그림 분석에서 탐지한 객체 Label, 신뢰도와 원본 이미지 기준 픽셀 영역을 저장한다. */
@Entity
@Table(name = "analysis_detected_objects")
public class DrawingDetectedObject {

  private static final BigDecimal ZERO = BigDecimal.ZERO;
  private static final BigDecimal ONE = BigDecimal.ONE;

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  @Column(name = "detected_object_id")
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "analysis_id", nullable = false)
  private DrawingAnalysis drawingAnalysis;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "drawing_asset_id", nullable = false)
  private DrawingAsset drawingAsset;

  @Column(name = "object_code", length = 50)
  private String label;

  @Column(name = "confidence_score", precision = 5, scale = 4)
  private BigDecimal confidence;

  @Column(name = "bbox_x", precision = 12, scale = 3)
  private BigDecimal x;

  @Column(name = "bbox_y", precision = 12, scale = 3)
  private BigDecimal y;

  @Column(name = "bbox_width", precision = 12, scale = 3)
  private BigDecimal width;

  @Column(name = "bbox_height", precision = 12, scale = 3)
  private BigDecimal height;

  @Column(name = "detection_order")
  private int displayOrder;

  @Column(name = "model_version", length = 50)
  private String modelVersion;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected DrawingDetectedObject() {}

  private DrawingDetectedObject(
      String label,
      BigDecimal confidence,
      BigDecimal x,
      BigDecimal y,
      BigDecimal width,
      BigDecimal height,
      int displayOrder,
      String modelVersion,
      LocalDateTime createdAt) {
    this.label = requireText(label, "label");
    this.confidence = requireRange(confidence, ZERO, ONE, "confidence");
    this.x = requireMinimum(x, ZERO, true, "x");
    this.y = requireMinimum(y, ZERO, true, "y");
    this.width = requireMinimum(width, ZERO, false, "width");
    this.height = requireMinimum(height, ZERO, false, "height");
    if (displayOrder < 0) {
      throw new IllegalArgumentException("displayOrder must not be negative");
    }
    this.displayOrder = displayOrder;
    this.modelVersion = requireText(modelVersion, "modelVersion");
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
  }

  /**
   * 검증된 단일 객체 탐지 결과를 생성한다.
   *
   * @param label 객체 식별 Label
   * @param confidence 0 이상 1 이하의 탐지 신뢰도
   * @param x 좌측 상단 X 픽셀 좌표
   * @param y 좌측 상단 Y 픽셀 좌표
   * @param width 0보다 큰 픽셀 너비
   * @param height 0보다 큰 픽셀 높이
   * @param displayOrder 응답 순서를 보존하는 0 이상의 순번
   * @param modelVersion 탐지에 사용한 Model 버전
   * @param createdAt 서버가 결과를 저장한 UTC 시각
   * @return 아직 분석 실행에 연결되지 않은 탐지 결과
   * @throws IllegalArgumentException 값이 허용 범위를 벗어난 경우
   */
  public static DrawingDetectedObject detected(
      String label,
      BigDecimal confidence,
      BigDecimal x,
      BigDecimal y,
      BigDecimal width,
      BigDecimal height,
      int displayOrder,
      String modelVersion,
      LocalDateTime createdAt) {
    return new DrawingDetectedObject(
        label, confidence, x, y, width, height, displayOrder, modelVersion, createdAt);
  }

  void attachTo(DrawingAnalysis analysis) {
    if (drawingAnalysis != null) {
      throw new IllegalStateException("detection is already attached");
    }
    drawingAnalysis = Objects.requireNonNull(analysis, "analysis must not be null");
    drawingAsset = analysis.getDrawingAsset();
  }

  /**
   * @return 탐지 결과가 속한 분석 실행
   */
  public DrawingAnalysis getDrawingAnalysis() {
    return drawingAnalysis;
  }

  /**
   * @return 객체 식별 Label
   */
  public String getLabel() {
    return label;
  }

  /**
   * @return 0 이상 1 이하의 탐지 신뢰도
   */
  public BigDecimal getConfidence() {
    return confidence;
  }

  /**
   * @return 좌측 상단 X 픽셀 좌표
   */
  public BigDecimal getX() {
    return x;
  }

  /**
   * @return 좌측 상단 Y 픽셀 좌표
   */
  public BigDecimal getY() {
    return y;
  }

  /**
   * @return 객체 영역의 픽셀 너비
   */
  public BigDecimal getWidth() {
    return width;
  }

  /**
   * @return 객체 영역의 픽셀 높이
   */
  public BigDecimal getHeight() {
    return height;
  }

  /**
   * @return Client 응답에서의 탐지 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }

  private static String requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
    return value;
  }

  private static BigDecimal requireRange(
      BigDecimal value, BigDecimal minimum, BigDecimal maximum, String name) {
    Objects.requireNonNull(value, name + " must not be null");
    if (value.compareTo(minimum) < 0 || value.compareTo(maximum) > 0) {
      throw new IllegalArgumentException(name + " is out of range");
    }
    return value;
  }

  private static BigDecimal requireMinimum(
      BigDecimal value, BigDecimal minimum, boolean inclusive, String name) {
    Objects.requireNonNull(value, name + " must not be null");
    int comparison = value.compareTo(minimum);
    if (comparison < 0 || (!inclusive && comparison == 0)) {
      throw new IllegalArgumentException(name + " is out of range");
    }
    return value;
  }
}
