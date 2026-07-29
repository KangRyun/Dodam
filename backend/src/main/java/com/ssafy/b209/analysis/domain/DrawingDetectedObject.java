package com.ssafy.b209.analysis.domain;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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

/** 그림 분석에서 탐지한 객체 Label, 신뢰도, 좌표계가 명시된 영역을 저장한다. */
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

  @Column(name = "object_name", length = 100)
  private String objectName;

  @Column(name = "confidence_score", precision = 5, scale = 4)
  private BigDecimal confidence;

  @Column(name = "bbox_x", precision = 12, scale = 6)
  private BigDecimal x;

  @Column(name = "bbox_y", precision = 12, scale = 6)
  private BigDecimal y;

  @Column(name = "bbox_width", precision = 12, scale = 6)
  private BigDecimal width;

  @Column(name = "bbox_height", precision = 12, scale = 6)
  private BigDecimal height;

  @Column(name = "area_ratio", precision = 8, scale = 6)
  private BigDecimal areaRatio;

  @Enumerated(EnumType.STRING)
  @Column(name = "coordinate_space", nullable = false, length = 20)
  private DrawingCoordinateSpace coordinateSpace;

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
      String objectName,
      BigDecimal confidence,
      BigDecimal x,
      BigDecimal y,
      BigDecimal width,
      BigDecimal height,
      BigDecimal areaRatio,
      DrawingCoordinateSpace coordinateSpace,
      int displayOrder,
      String modelVersion,
      LocalDateTime createdAt) {
    this.label = requireText(label, "label");
    this.objectName = objectName;
    this.confidence = requireRange(confidence, ZERO, ONE, "confidence");
    this.coordinateSpace =
        Objects.requireNonNull(coordinateSpace, "coordinateSpace must not be null");
    this.x = requireCoordinate(x, true, "x");
    this.y = requireCoordinate(y, true, "y");
    this.width = requireCoordinate(width, false, "width");
    this.height = requireCoordinate(height, false, "height");
    if (coordinateSpace == DrawingCoordinateSpace.NORMALIZED
        && (x.add(width).compareTo(ONE) > 0 || y.add(height).compareTo(ONE) > 0)) {
      throw new IllegalArgumentException("normalized bounding box is outside canvas");
    }
    this.areaRatio = areaRatio == null ? null : requireRange(areaRatio, ZERO, ONE, "areaRatio");
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
        label,
        null,
        confidence,
        x,
        y,
        width,
        height,
        null,
        DrawingCoordinateSpace.PIXEL,
        displayOrder,
        modelVersion,
        createdAt);
  }

  /**
   * 정본 AI 응답의 객체명, 면적 비율과 탐지 순서를 보존하는 탐지 결과를 생성한다.
   *
   * @param objectCode 계약에서 사용하는 객체 코드
   * @param objectName 사용자 표시용 객체명
   * @param confidence 0~1 탐지 신뢰도
   * @param x 0~1 정규화 X 좌표
   * @param y 0~1 정규화 Y 좌표
   * @param width 0~1 정규화 너비
   * @param height 0~1 정규화 높이
   * @param areaRatio 전체 그림에서 객체가 차지하는 비율
   * @param detectionOrder AI 응답의 탐지 순서
   * @param modelVersion 객체 탐지 Model 버전
   * @param createdAt 결과 저장 UTC 시각
   * @return 아직 분석 실행에 연결되지 않은 탐지 결과
   */
  public static DrawingDetectedObject detected(
      String objectCode,
      String objectName,
      BigDecimal confidence,
      BigDecimal x,
      BigDecimal y,
      BigDecimal width,
      BigDecimal height,
      BigDecimal areaRatio,
      int detectionOrder,
      String modelVersion,
      LocalDateTime createdAt) {
    return new DrawingDetectedObject(
        objectCode,
        objectName,
        confidence,
        x,
        y,
        width,
        height,
        areaRatio,
        DrawingCoordinateSpace.NORMALIZED,
        detectionOrder,
        modelVersion,
        createdAt);
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
   * @return 저장된 탐지 객체 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 객체 식별 Label
   */
  public String getLabel() {
    return label;
  }

  /**
   * @return 사용자 표시용 객체명이며 제공되지 않았으면 {@code null}
   */
  public String getObjectName() {
    return objectName;
  }

  /**
   * @return 0 이상 1 이하의 탐지 신뢰도
   */
  public BigDecimal getConfidence() {
    return confidence;
  }

  /**
   * @return 현재 {@link #getCoordinateSpace()} 기준의 좌측 상단 X 좌표
   */
  public BigDecimal getX() {
    return x;
  }

  /**
   * @return 현재 {@link #getCoordinateSpace()} 기준의 좌측 상단 Y 좌표
   */
  public BigDecimal getY() {
    return y;
  }

  /**
   * @return 현재 {@link #getCoordinateSpace()} 기준의 객체 영역 너비
   */
  public BigDecimal getWidth() {
    return width;
  }

  /**
   * @return 현재 {@link #getCoordinateSpace()} 기준의 객체 영역 높이
   */
  public BigDecimal getHeight() {
    return height;
  }

  /**
   * @return 전체 그림에서 객체 영역이 차지하는 비율이며 제공되지 않았으면 {@code null}
   */
  public BigDecimal getAreaRatio() {
    return areaRatio;
  }

  /**
   * @return Bounding Box에 적용되는 픽셀 또는 정규화 좌표계
   */
  public DrawingCoordinateSpace getCoordinateSpace() {
    return coordinateSpace;
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

  private BigDecimal requireCoordinate(BigDecimal value, boolean inclusive, String name) {
    BigDecimal coordinate = requireMinimum(value, ZERO, inclusive, name);
    if (coordinateSpace == DrawingCoordinateSpace.NORMALIZED && coordinate.compareTo(ONE) > 0) {
      throw new IllegalArgumentException(name + " is out of normalized range");
    }
    return coordinate;
  }
}
