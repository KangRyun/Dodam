package com.ssafy.b209.drawing.domain;

public final class DrawingTypeFixture {

  private DrawingTypeFixture() {}

  public static DrawingType create(
      Long id,
      String code,
      String name,
      DrawingTypeSelectableBy selectableBy,
      Integer recommendedAgeMin,
      Integer recommendedAgeMax,
      boolean active) {
    return new DrawingType(
        id,
        code,
        name,
        DrawingActivityCategory.GENERAL,
        selectableBy,
        recommendedAgeMin,
        recommendedAgeMax,
        active);
  }
}
