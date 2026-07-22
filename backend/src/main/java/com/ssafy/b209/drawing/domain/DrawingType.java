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

/** 그림 활동 시작 시 선택 가능한 그림 유형과 권장 연령 범위를 관리한다. */
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

  @Column(name = "is_active", nullable = false)
  private boolean active;

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
   * 활성 상태와 권장 연령의 양 끝값을 포함해 선택 가능 여부를 판단한다.
   *
   * @param age 유형을 선택하려는 아동의 만 나이
   * @return 활성 유형이고 권장 연령 범위에 포함되면 {@code true}
   */
  public boolean isAvailableForAge(int age) {
    return active
        && age >= 0
        && (recommendedAgeMin == null || age >= recommendedAgeMin)
        && (recommendedAgeMax == null || age <= recommendedAgeMax);
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
}
