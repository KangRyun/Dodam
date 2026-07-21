package com.ssafy.b209.drawing.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class DrawingTypeDomainTest {

  @Test
  void isAvailableForAgeUsesInclusiveConfiguredBoundaries() {
    DrawingType drawingType =
        DrawingTypeFixture.create(3L, "HOUSE", "House", DrawingTypeSelectableBy.BOTH, 6, 10, true);

    assertThat(drawingType.isAvailableForAge(5)).isFalse();
    assertThat(drawingType.isAvailableForAge(6)).isTrue();
    assertThat(drawingType.isAvailableForAge(10)).isTrue();
    assertThat(drawingType.isAvailableForAge(11)).isFalse();
    assertThat(drawingType.getId()).isEqualTo(3L);
    assertThat(drawingType.getCode()).isEqualTo("HOUSE");
    assertThat(drawingType.getName()).isEqualTo("House");
  }

  @Test
  void isAvailableForAgeAllowsAbsentBoundariesButNeverNegativeAgeOrInactiveTypes() {
    DrawingType unbounded =
        DrawingTypeFixture.create(
            3L, "HOUSE", "House", DrawingTypeSelectableBy.BOTH, null, null, true);
    DrawingType inactive =
        DrawingTypeFixture.create(
            4L, "TREE", "Tree", DrawingTypeSelectableBy.CHILD, null, null, false);

    assertThat(unbounded.isAvailableForAge(0)).isTrue();
    assertThat(unbounded.isAvailableForAge(-1)).isFalse();
    assertThat(inactive.isAvailableForAge(7)).isFalse();
  }
}
