package com.ssafy.b209.child.domain;

import java.time.LocalDate;
import java.time.LocalDateTime;

public final class ChildFixture {

  private ChildFixture() {}

  public static Child create(
      Long id,
      LocalDate birthDate,
      ChildTutorialStatus tutorialStatus,
      ChildProfileStatus profileStatus,
      LocalDateTime deletedAt) {
    return new Child(id, "fixture-child", birthDate, tutorialStatus, profileStatus, deletedAt);
  }
}
