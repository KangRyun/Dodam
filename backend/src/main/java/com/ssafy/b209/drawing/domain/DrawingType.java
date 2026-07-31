package com.ssafy.b209.drawing.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.util.Objects;

/**
 * 그림 활동 시작 시 선택 가능한 유형과 화면 안내용 권장 연령 Metadata를 관리한다.
 *
 * <p>권장 연령은 보호자에게 제공하는 참고 정보이며 활동 노출이나 시작을 제한하지 않는다.
 */
@Entity
@Table(name = "drawing_types")
public class DrawingType {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(nullable = false)
  private String code;

  @Column(nullable = false)
  private String name;

  @Enumerated(EnumType.STRING)
  @Column(name = "activity_category", nullable = false)
  private DrawingActivityCategory activityCategory;

  @Enumerated(EnumType.STRING)
  @Column(name = "selectable_by", nullable = false)
  private DrawingTypeSelectableBy selectableBy;

  @Column(name = "recommended_age_min", columnDefinition = "TINYINT")
  private Integer recommendedAgeMin;

  @Column(name = "recommended_age_max", columnDefinition = "TINYINT")
  private Integer recommendedAgeMax;

  @Column(name = "guide_text", columnDefinition = "TEXT")
  private String guideText;

  @Column(name = "is_active", nullable = false)
  private boolean active;

  @Column(name = "display_order", nullable = false, columnDefinition = "SMALLINT DEFAULT 0")
  private short displayOrder;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected DrawingType() {}

  DrawingType(
      Long id,
      String code,
      String name,
      DrawingActivityCategory activityCategory,
      DrawingTypeSelectableBy selectableBy,
      Integer recommendedAgeMin,
      Integer recommendedAgeMax,
      boolean active) {
    this.id = id;
    this.code = Objects.requireNonNull(code, "code must not be null");
    this.name = Objects.requireNonNull(name, "name must not be null");
    this.activityCategory =
        Objects.requireNonNull(activityCategory, "activityCategory must not be null");
    this.selectableBy = Objects.requireNonNull(selectableBy, "selectableBy must not be null");
    this.recommendedAgeMin = recommendedAgeMin;
    this.recommendedAgeMax = recommendedAgeMax;
    this.active = active;
  }

  /**
   * 사용자에게 제공 가능한 활성 유형인지 확인한다.
   *
   * <p>권장 연령 범위는 화면 안내를 위한 Metadata이며 활동 선택이나 시작을 제한하지 않는다.
   *
   * @return 운영 중인 그림 활동 유형이면 {@code true}
   */
  public boolean isActive() {
    return active;
  }

  /**
   * 그림 활동 유형 식별자를 반환한다.
   *
   * @return 영속화된 유형 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * 그림 활동 유형의 안정적인 업무 코드를 반환한다.
   *
   * @return 그림 활동 유형 코드
   */
  public String getCode() {
    return code;
  }

  /**
   * 사용자에게 표시할 그림 활동 유형 이름을 반환한다.
   *
   * @return 그림 활동 유형 이름
   */
  public String getName() {
    return name;
  }

  /**
   * 그림 활동 유형의 분류를 반환한다.
   *
   * @return 평가 목적 또는 일반 활동 분류
   */
  public DrawingActivityCategory getActivityCategory() {
    return activityCategory;
  }

  /**
   * 그림 활동 유형을 선택할 수 있는 주체를 반환한다.
   *
   * @return 보호자, 아동 또는 양쪽 선택 가능 여부
   */
  public DrawingTypeSelectableBy getSelectableBy() {
    return selectableBy;
  }

  /**
   * 권장 최소 연령을 반환한다.
   *
   * @return 제한이 없으면 {@code null}, 있으면 포함되는 최소 만 나이
   */
  public Integer getRecommendedAgeMin() {
    return recommendedAgeMin;
  }

  /**
   * 권장 최대 연령을 반환한다.
   *
   * @return 제한이 없으면 {@code null}, 있으면 포함되는 최대 만 나이
   */
  public Integer getRecommendedAgeMax() {
    return recommendedAgeMax;
  }

  /**
   * 아동에게 보여줄 활동 안내 문구를 반환한다.
   *
   * @return 별도 안내가 없으면 {@code null}
   */
  public String getGuideText() {
    return guideText;
  }

  /**
   * 그림 유형 목록의 기본 노출 순서를 반환한다.
   *
   * @return 값이 작을수록 먼저 노출되는 순서
   */
  public int getDisplayOrder() {
    return displayOrder;
  }
}
