package com.ssafy.b209.child.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.Period;
import java.util.Objects;

/** 그림 활동을 시작할 수 있는 아동의 최소 프로필 정보를 관리한다. */
@Entity
@Table(name = "children")
public class Child {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(nullable = false)
  private String nickname;

  @Column(name = "birth_date", nullable = false)
  private LocalDate birthDate;

  @Enumerated(EnumType.STRING)
  @Column(name = "tutorial_status", nullable = false)
  private ChildTutorialStatus tutorialStatus;

  @Enumerated(EnumType.STRING)
  @Column(name = "profile_status", nullable = false)
  private ChildProfileStatus profileStatus;

  @Column(name = "deleted_at")
  private LocalDateTime deletedAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected Child() {}

  Child(
      Long id,
      String nickname,
      LocalDate birthDate,
      ChildTutorialStatus tutorialStatus,
      ChildProfileStatus profileStatus,
      LocalDateTime deletedAt) {
    this.id = id;
    this.nickname = Objects.requireNonNull(nickname, "nickname must not be null");
    this.birthDate = Objects.requireNonNull(birthDate, "birthDate must not be null");
    this.tutorialStatus = Objects.requireNonNull(tutorialStatus, "tutorialStatus must not be null");
    this.profileStatus = Objects.requireNonNull(profileStatus, "profileStatus must not be null");
    this.deletedAt = deletedAt;
  }

  /**
   * 프로필 상태와 삭제 시각을 함께 고려해 그림 활동에 사용할 수 있는지 확인한다.
   *
   * @return 활성 프로필이며 삭제되지 않았으면 {@code true}
   */
  public boolean isAvailable() {
    return profileStatus == ChildProfileStatus.ACTIVE && deletedAt == null;
  }

  /**
   * 완료하거나 건너뛰지 않은 아동에게 안내 진행이 필요한지 확인한다.
   *
   * @return 그림 활동 Tutorial 안내가 필요하면 {@code true}
   */
  public boolean isTutorialRequired() {
    return tutorialStatus != ChildTutorialStatus.COMPLETED
        && tutorialStatus != ChildTutorialStatus.SKIPPED;
  }

  /**
   * 기준일을 사용해 시스템 시각과 무관하게 만 나이를 계산한다.
   *
   * @param date 나이를 계산할 기준일
   * @return 기준일 현재의 만 나이
   */
  public int ageOn(LocalDate date) {
    Objects.requireNonNull(date, "date must not be null");
    return Period.between(birthDate, date).getYears();
  }

  /**
   * 아동 식별자를 반환한다.
   *
   * @return 영속화된 아동 식별자
   */
  public Long getId() {
    return id;
  }
}
