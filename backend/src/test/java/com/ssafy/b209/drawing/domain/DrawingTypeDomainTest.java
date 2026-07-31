package com.ssafy.b209.drawing.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class DrawingTypeDomainTest {

  @Test
  void exposesActiveStateAndRecommendedAgeMetadataSeparately() {
    DrawingType drawingType =
        DrawingTypeFixture.create(3L, "HOUSE", "House", DrawingTypeSelectableBy.BOTH, 6, 10, true);

    assertThat(drawingType.isActive()).isTrue();
    assertThat(drawingType.getRecommendedAgeMin()).isEqualTo(6);
    assertThat(drawingType.getRecommendedAgeMax()).isEqualTo(10);
    assertThat(drawingType.getId()).isEqualTo(3L);
    assertThat(drawingType.getCode()).isEqualTo("HOUSE");
    assertThat(drawingType.getName()).isEqualTo("House");
  }

  @Test
  void reportsInactiveTypeWithoutInterpretingRecommendedAge() {
    DrawingType inactive =
        DrawingTypeFixture.create(4L, "TREE", "Tree", DrawingTypeSelectableBy.CHILD, 6, 10, false);

    assertThat(inactive.isActive()).isFalse();
    assertThat(inactive.getRecommendedAgeMin()).isEqualTo(6);
    assertThat(inactive.getRecommendedAgeMax()).isEqualTo(10);
  }
}
