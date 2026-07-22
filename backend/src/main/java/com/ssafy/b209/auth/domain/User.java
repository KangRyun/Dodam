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

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

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
}
