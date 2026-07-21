package com.ssafy.b209.child.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.LocalDate;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class ChildDomainTest {

  @Test
  void isAvailableRequiresAnActiveProfileWithoutDeletionTime() {
    Child available =
        ChildFixture.create(
            1L,
            LocalDate.of(2018, 7, 21),
            ChildTutorialStatus.NOT_STARTED,
            ChildProfileStatus.ACTIVE,
            null);
    Child deleted =
        ChildFixture.create(
            2L,
            LocalDate.of(2018, 7, 21),
            ChildTutorialStatus.NOT_STARTED,
            ChildProfileStatus.ACTIVE,
            LocalDateTime.of(2026, 7, 21, 12, 0));

    assertThat(available.isAvailable()).isTrue();
    assertThat(deleted.isAvailable()).isFalse();
  }

  @Test
  void isTutorialRequiredOnlyUntilCompletionOrSkipping() {
    Child inProgress =
        ChildFixture.create(
            1L,
            LocalDate.of(2018, 7, 21),
            ChildTutorialStatus.IN_PROGRESS,
            ChildProfileStatus.ACTIVE,
            null);
    Child completed =
        ChildFixture.create(
            2L,
            LocalDate.of(2018, 7, 21),
            ChildTutorialStatus.COMPLETED,
            ChildProfileStatus.ACTIVE,
            null);
    Child skipped =
        ChildFixture.create(
            3L,
            LocalDate.of(2018, 7, 21),
            ChildTutorialStatus.SKIPPED,
            ChildProfileStatus.ACTIVE,
            null);

    assertThat(inProgress.isTutorialRequired()).isTrue();
    assertThat(completed.isTutorialRequired()).isFalse();
    assertThat(skipped.isTutorialRequired()).isFalse();
  }

  @Test
  void ageOnChangesOnTheBirthdayBoundary() {
    Child child =
        ChildFixture.create(
            9L,
            LocalDate.of(2018, 7, 21),
            ChildTutorialStatus.NOT_STARTED,
            ChildProfileStatus.ACTIVE,
            null);

    assertThat(child.ageOn(LocalDate.of(2026, 7, 20))).isEqualTo(7);
    assertThat(child.ageOn(LocalDate.of(2026, 7, 21))).isEqualTo(8);
    assertThat(child.getId()).isEqualTo(9L);
  }

  @Test
  void ageOnRejectsNullDate() {
    Child child =
        ChildFixture.create(
            1L,
            LocalDate.of(2018, 7, 21),
            ChildTutorialStatus.NOT_STARTED,
            ChildProfileStatus.ACTIVE,
            null);

    assertThatThrownBy(() -> child.ageOn(null)).isInstanceOf(NullPointerException.class);
  }
}
