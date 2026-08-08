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

  @Enumerated(EnumType.STRING)
  @Column(name = "question_difficulty", nullable = false)
  private QuestionDifficulty questionDifficulty;

  /**
   * 아이가 지금 다니는 곳이며 미입력이면 {@code null} (S15P11B209-1010 v2).
   *
   * <p><strong>{@code null} 이 정상이다.</strong> 필수로 받지 않고, '모른다'를 값으로 두지도 않는다 — 값으로
   * 두면 "모른다고 고른 것"과 "고르지 않은 것"을 구별할 수 없다. 응답 DTO 에서만 {@code UNKNOWN} 으로
   * 바꿔 내보낸다.
   */
  @Enumerated(EnumType.STRING)
  @Column(name = "education_stage", length = 20)
  private EducationStage educationStage;

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
      QuestionDifficulty questionDifficulty,
      LocalDateTime deletedAt) {
    this.id = id;
    this.nickname = Objects.requireNonNull(nickname, "nickname must not be null");
    this.birthDate = Objects.requireNonNull(birthDate, "birthDate must not be null");
    this.tutorialStatus = Objects.requireNonNull(tutorialStatus, "tutorialStatus must not be null");
    this.profileStatus = Objects.requireNonNull(profileStatus, "profileStatus must not be null");
    this.questionDifficulty =
        Objects.requireNonNull(questionDifficulty, "questionDifficulty must not be null");
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
   * 기준일 현재의 만 나이를 <strong>개월</strong>로 계산한다 (S15P11B209-1010 v2).
   *
   * <p>연 단위를 12배 하는 방식을 대신한다. 그 값은 구간 경계에서 한 해가 통째로 움직여
   * <strong>72~83개월처럼 한 해 안을 가르는 구간을 만들 수 없었다.</strong> 생일이 있으니
   * 개월을 그대로 계산하는 것이 맞다.
   *
   * @param date 나이를 계산할 기준일
   * @return 기준일 현재의 만 나이(개월). 기준일이 생일보다 앞서면 0
   */
  public int ageMonthsOn(LocalDate date) {
    Objects.requireNonNull(date, "date must not be null");
    if (date.isBefore(birthDate)) {
      return 0;
    }
    Period period = Period.between(birthDate, date);
    return period.getYears() * 12 + period.getMonths();
  }

  /**
   * @return 아이가 다니는 곳이며 미입력이면 {@code null}
   */
  public EducationStage getEducationStage() {
    return educationStage;
  }

  /**
   * 다니는 곳을 바꾼다.
   *
   * <p>{@code null} 은 "고르지 않음"이며 지우는 것도 정상 동작이다 — 보호자가 잘못 골랐을 때 되돌릴 수 있어야
   * 한다.
   *
   * @param educationStage 새 교육단계이며 비우려면 {@code null}
   */
  public void changeEducationStage(EducationStage educationStage) {
    this.educationStage = educationStage;
  }

  /**
   * 아동 식별자를 반환한다.
   *
   * @return 영속화된 아동 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * 보호자 화면에 표시할 아동 별칭을 반환한다.
   *
   * @return 아동 별칭
   */
  public String getNickname() {
    return nickname;
  }

  /**
   * DB v1.2와 API 계약에 따른 아동의 질문 난이도를 반환한다.
   *
   * @return 아동 질문 생성에 사용할 난이도
   */
  public QuestionDifficulty getQuestionDifficulty() {
    return questionDifficulty;
  }
}
