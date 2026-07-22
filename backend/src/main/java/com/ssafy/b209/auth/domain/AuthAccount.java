package com.ssafy.b209.auth.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * OAuth Provider가 보증한 외부 계정과 서비스 사용자의 연결을 관리한다.
 *
 * <p>계정 식별은 변경 가능한 이메일이나 전화번호가 아니라 {@code provider}와 {@code providerSubject}의 조합으로 수행한다.
 */
@Entity
@Table(
    name = "auth_accounts",
    uniqueConstraints =
        @UniqueConstraint(
            name = "uk_auth_accounts_provider_subject",
            columnNames = {"provider", "provider_subject"}))
public class AuthAccount {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "user_id", nullable = false)
  private User user;

  @Enumerated(EnumType.STRING)
  @Column(name = "provider", nullable = false, length = 20)
  private AuthProvider provider;

  @Column(name = "provider_subject", nullable = false, length = 255)
  private String providerSubject;

  @Column(name = "provider_email", length = 255)
  private String providerEmail;

  @Column(name = "provider_email_verified_at")
  private LocalDateTime providerEmailVerifiedAt;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  /** JPA가 Entity를 복원할 때 사용한다. */
  protected AuthAccount() {}

  private AuthAccount(
      User user,
      AuthProvider provider,
      String providerSubject,
      String providerEmail,
      LocalDateTime providerEmailVerifiedAt,
      LocalDateTime createdAt) {
    this.user = Objects.requireNonNull(user, "user must not be null");
    this.provider = Objects.requireNonNull(provider, "provider must not be null");
    this.providerSubject = requireSubject(providerSubject);
    this.providerEmail = providerEmail;
    this.providerEmailVerifiedAt = providerEmailVerifiedAt;
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
    this.updatedAt = createdAt;
  }

  /**
   * 검증된 OAuth 신원과 사용자를 연결하는 인증 계정을 생성한다.
   *
   * @param user 연결할 서비스 사용자
   * @param provider OAuth Provider
   * @param providerSubject Provider가 발급한 불변 사용자 식별자
   * @param providerEmail Provider가 검증한 이메일, 제공되지 않았으면 {@code null}
   * @param providerEmailVerifiedAt 이메일 검증 확인 시각, 이메일이 없으면 {@code null}
   * @param now 인증 계정 생성 시각
   * @return 생성할 OAuth 인증 계정
   */
  public static AuthAccount social(
      User user,
      AuthProvider provider,
      String providerSubject,
      String providerEmail,
      LocalDateTime providerEmailVerifiedAt,
      LocalDateTime now) {
    return new AuthAccount(
        user, provider, providerSubject, providerEmail, providerEmailVerifiedAt, now);
  }

  /**
   * 연결된 서비스 사용자를 반환한다.
   *
   * @return OAuth 계정 소유자
   */
  public User getUser() {
    return user;
  }

  /**
   * OAuth Provider를 반환한다.
   *
   * @return 인증 계정을 보증한 Provider
   */
  public AuthProvider getProvider() {
    return provider;
  }

  /**
   * Provider가 검증하여 전달한 보조 이메일을 반환한다.
   *
   * @return 검증된 이메일 또는 제공되지 않은 경우 {@code null}
   */
  public String getProviderEmail() {
    return providerEmail;
  }

  /**
   * 보조 이메일의 검증 확인 시각을 반환한다.
   *
   * @return 검증 확인 시각 또는 이메일이 없는 경우 {@code null}
   */
  public LocalDateTime getProviderEmailVerifiedAt() {
    return providerEmailVerifiedAt;
  }

  private static String requireSubject(String providerSubject) {
    if (providerSubject == null || providerSubject.isBlank()) {
      throw new IllegalArgumentException("providerSubject must not be blank");
    }
    return providerSubject.trim();
  }
}
