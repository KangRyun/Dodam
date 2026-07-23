package com.ssafy.b209.child.domain;

import java.time.LocalDate;
import java.time.LocalDateTime;

public final class ChildFixture {

  private ChildFixture() {}

  /**
   * DB 기본값과 같은 {@link QuestionDifficulty#PRESCHOOL} 난이도의 아동 Fixture를 만든다.
   *
   * @param id 아동 식별자
   * @param birthDate 생년월일
   * @param tutorialStatus Tutorial 진행 상태
   * @param profileStatus 프로필 상태
   * @param deletedAt 삭제 시각
   * @return 테스트에 사용할 아동
   */
  public static Child create(
      Long id,
      LocalDate birthDate,
      ChildTutorialStatus tutorialStatus,
      ChildProfileStatus profileStatus,
      LocalDateTime deletedAt) {
    return create(
        id, birthDate, tutorialStatus, profileStatus, QuestionDifficulty.PRESCHOOL, deletedAt);
  }

  /**
   * 지정한 질문 난이도를 포함한 아동 Fixture를 만든다.
   *
   * @param id 아동 식별자
   * @param birthDate 생년월일
   * @param tutorialStatus Tutorial 진행 상태
   * @param profileStatus 프로필 상태
   * @param questionDifficulty 질문 생성 난이도
   * @param deletedAt 삭제 시각
   * @return 테스트에 사용할 아동
   */
  public static Child create(
      Long id,
      LocalDate birthDate,
      ChildTutorialStatus tutorialStatus,
      ChildProfileStatus profileStatus,
      QuestionDifficulty questionDifficulty,
      LocalDateTime deletedAt) {
    return new Child(
        id,
        "fixture-child",
        birthDate,
        tutorialStatus,
        profileStatus,
        questionDifficulty,
        deletedAt);
  }
}
