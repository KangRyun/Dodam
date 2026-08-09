package com.ssafy.b209.auth.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * 인증 계정과 서비스 프로필이 공유하는 사용자 식별자를 관리한다.
 *
 * <p>첫 OAuth 로그인 시 역할이 정해지지 않은 {@link AccountStatus#PENDING} 상태로 생성되며, 이후 Onboarding에서 역할과 프로필을
 * 완성한다. OAuth Provider의 식별 정보는 {@link AuthAccount}가 담당한다.
 */
@Entity
@Table(name = "users")
public class User {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Enumerated(EnumType.STRING)
  @Column(name = "role")
  private UserRole role;

  @Enumerated(EnumType.STRING)
  @Column(name = "account_status", nullable = false, length = 20)
  private AccountStatus accountStatus;

  @Column(name = "is_completed", nullable = false)
  private boolean onboardingCompleted;

  @Column(name = "nickname", length = 50)
  private String nickname;

  @Column(name = "email", length = 255)
  private String email;

  @Column(name = "profile_image_url", length = 1000)
  private String profileImageUrl;

  @Column(name = "last_login_at")
  private LocalDateTime lastLoginAt;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  @Column(name = "deleted_at")
  private LocalDateTime deletedAt;

  /** JPA가 Entity를 복원할 때 사용한다. */
  protected User() {}

  private User(
      UserRole role,
      AccountStatus accountStatus,
      boolean onboardingCompleted,
      LocalDateTime createdAt,
      LocalDateTime updatedAt) {
    this.role = role;
    this.accountStatus = Objects.requireNonNull(accountStatus, "accountStatus must not be null");
    this.onboardingCompleted = onboardingCompleted;
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
    this.updatedAt = Objects.requireNonNull(updatedAt, "updatedAt must not be null");
  }

  /**
   * 최초 OAuth 로그인을 마친 Onboarding 대기 사용자를 생성한다.
   *
   * @param now 계정 생성 및 수정 시각
   * @return 역할이 아직 없고 Onboarding이 완료되지 않은 사용자
   */
  public static User pending(LocalDateTime now) {
    return new User(null, AccountStatus.PENDING, false, now, now);
  }

  /**
   * 영속화된 사용자 식별자를 반환한다.
   *
   * @return 사용자 ID
   */
  public Long getId() {
    return id;
  }

  /**
   * 필수 역할과 프로필 입력을 완료했는지 확인한다.
   *
   * @return Onboarding이 완료되었으면 {@code true}
   */
  public boolean isOnboardingCompleted() {
    return onboardingCompleted;
  }

  /**
   * 사용자 역할을 반환한다.
   *
   * @return Onboarding 전이면 {@code null}, 완료 후에는 확정된 역할
   */
  public UserRole getRole() {
    return role;
  }

  /**
   * 계정 이용 상태를 반환한다.
   *
   * @return 현재 계정 상태
   */
  public AccountStatus getAccountStatus() {
    return accountStatus;
  }

  /**
   * 사용자 표시 이름을 반환한다.
   *
   * @return Onboarding에서 입력한 닉네임 또는 입력 전이면 {@code null}
   */
  public String getNickname() {
    return nickname;
  }

  /**
   * 사용자 연락 이메일을 반환한다.
   *
   * @return Onboarding에서 확정한 이메일 또는 확정 전이면 {@code null}
   */
  public String getEmail() {
    return email;
  }

  /**
   * 최초 사용자 정보를 확정하고 Onboarding을 완료 상태로 전이한다.
   *
   * <p>역할, 닉네임, 연락 이메일을 저장하고 계정을 이용 가능한 {@link AccountStatus#ACTIVE}로 전환한다.
   *
   * @param role 사용자가 선택한 역할
   * @param nickname 사용자 표시 이름
   * @param email 사용자 연락 이메일
   * @param now 온보딩 처리 시각
   */
  public void completeOnboarding(UserRole role, String nickname, String email, LocalDateTime now) {
    this.role = Objects.requireNonNull(role, "role must not be null");
    this.nickname = Objects.requireNonNull(nickname, "nickname must not be null");
    this.email = Objects.requireNonNull(email, "email must not be null");
    this.accountStatus = AccountStatus.ACTIVE;
    this.onboardingCompleted = true;
    this.updatedAt = Objects.requireNonNull(now, "now must not be null");
  }

  /**
   * 사용자 표시 이름을 변경한다.
   *
   * @param nickname 변경할 닉네임
   * @param now 변경 처리 시각
   */
  public void changeNickname(String nickname, LocalDateTime now) {
    this.nickname = Objects.requireNonNull(nickname, "nickname must not be null");
    this.updatedAt = Objects.requireNonNull(now, "now must not be null");
  }

  /**
   * 성공한 로그인 시각을 갱신한다.
   *
   * @param loggedInAt Provider 인증과 서비스 계정 확인을 마친 시각
   */
  public void recordSuccessfulLogin(LocalDateTime loggedInAt) {
    this.lastLoginAt = Objects.requireNonNull(loggedInAt, "loggedInAt must not be null");
    this.updatedAt = loggedInAt;
  }

  /**
   * 계정을 삭제 상태로 전환한다.
   *
   * <p>사용자 행은 보존하고, 이후 인증 경계가 {@link AccountStatus#DELETED} 상태를 차단한다.
   *
   * @param deletedAt 삭제 처리 시각
   */
  public void markDeleted(LocalDateTime deletedAt) {
    this.accountStatus = AccountStatus.DELETED;
    this.deletedAt = Objects.requireNonNull(deletedAt, "deletedAt must not be null");
    this.updatedAt = deletedAt;
  }

  /**
   * 사용자 프로필 이미지 URL을 반환한다.
   *
   * @return 저장된 프로필 이미지 URL 또는 등록 전이면 {@code null}
   */
  public String getProfileImageUrl() {
    return profileImageUrl;
  }

  /**
   * 마지막 로그인 시각을 반환한다.
   *
   * @return 최근 로그인 시각 또는 로그인 기록이 없으면 {@code null}
   */
  public LocalDateTime getLastLoginAt() {
    return lastLoginAt;
  }

  /**
   * 계정 생성 시각을 반환한다.
   *
   * @return 계정 생성 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }
}
