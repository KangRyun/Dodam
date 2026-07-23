package com.ssafy.b209.consent.domain;

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

/** 버전별 약관 내용과 적용 대상·필수 여부·시행 상태를 관리한다. */
@Entity
@Table(name = "consent_terms")
public class ConsentTerm {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "term_code", nullable = false, length = 50)
  private String termCode;

  @Enumerated(EnumType.STRING)
  @Column(name = "target_scope", nullable = false, length = 10)
  private ConsentTargetScope targetScope;

  @Column(name = "is_required", nullable = false)
  private boolean required;

  @Column(nullable = false, length = 30)
  private String version;

  @Column(nullable = false, length = 150)
  private String title;

  @Column(name = "content_url", length = 1000)
  private String contentUrl;

  @Column(name = "content_html", columnDefinition = "TEXT")
  private String contentHtml;

  @Column(name = "effective_at", nullable = false)
  private LocalDateTime effectiveAt;

  @Column(name = "is_active", nullable = false)
  private boolean active;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  /** JPA가 약관 Entity를 복원할 때 사용한다. */
  protected ConsentTerm() {}

  private ConsentTerm(
      String termCode,
      ConsentTargetScope targetScope,
      boolean required,
      String version,
      String title,
      String contentUrl,
      LocalDateTime effectiveAt,
      boolean active,
      LocalDateTime createdAt) {
    this.termCode = Objects.requireNonNull(termCode, "termCode must not be null");
    this.targetScope = Objects.requireNonNull(targetScope, "targetScope must not be null");
    this.required = required;
    this.version = Objects.requireNonNull(version, "version must not be null");
    this.title = Objects.requireNonNull(title, "title must not be null");
    this.contentUrl = contentUrl;
    this.effectiveAt = Objects.requireNonNull(effectiveAt, "effectiveAt must not be null");
    this.active = active;
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
  }

  /**
   * 테스트와 향후 약관 관리 기능에서 사용할 버전 약관을 정의한다.
   *
   * @param termCode 기능에서 식별할 안정적인 약관 코드
   * @param targetScope 동의 적용 대상
   * @param required 서비스 이용에 필수인지 여부
   * @param version 변경 불가능한 약관 버전
   * @param title 사용자에게 표시할 제목
   * @param contentUrl 약관 원문 URL
   * @param effectiveAt 약관 시행 시각
   * @param active 현재 신규 동의를 받을 수 있는지 여부
   * @param createdAt 생성 시각
   * @return 저장 가능한 약관 Entity
   */
  public static ConsentTerm define(
      String termCode,
      ConsentTargetScope targetScope,
      boolean required,
      String version,
      String title,
      String contentUrl,
      LocalDateTime effectiveAt,
      boolean active,
      LocalDateTime createdAt) {
    return new ConsentTerm(
        termCode,
        targetScope,
        required,
        version,
        title,
        contentUrl,
        effectiveAt,
        active,
        createdAt);
  }

  /**
   * 약관 식별자를 반환한다.
   *
   * @return 약관 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * 약관의 동의 적용 범위를 반환한다.
   *
   * @return 사용자 또는 아동 동의 적용 범위
   */
  public ConsentTargetScope getTargetScope() {
    return targetScope;
  }

  /**
   * 서비스 이용에 필수인 약관인지 확인한다.
   *
   * @return 서비스 이용 필수 약관이면 {@code true}
   */
  public boolean isRequired() {
    return required;
  }

  /**
   * 기능에서 약관을 식별하는 안정적인 코드를 반환한다.
   *
   * @return 약관 코드
   */
  public String getTermCode() {
    return termCode;
  }

  /**
   * 변경 불가능한 약관 버전을 반환한다.
   *
   * @return 약관 버전
   */
  public String getVersion() {
    return version;
  }

  /**
   * 사용자에게 표시할 약관 제목을 반환한다.
   *
   * @return 약관 제목
   */
  public String getTitle() {
    return title;
  }

  /**
   * 약관 원문 URL을 반환한다.
   *
   * @return 약관 원문 URL 또는 {@code null}
   */
  public String getContentUrl() {
    return contentUrl;
  }

  /**
   * 약관 원문 HTML을 반환한다.
   *
   * @return 약관 원문 HTML 또는 아직 확정되지 않았으면 {@code null}
   */
  public String getContentHtml() {
    return contentHtml;
  }

  /**
   * 약관 시행 시각을 반환한다.
   *
   * @return 약관 시행 시각
   */
  public LocalDateTime getEffectiveAt() {
    return effectiveAt;
  }

  /**
   * 지정 시각에 신규 동의를 받을 수 있는 버전인지 확인한다.
   *
   * @param now 서버가 판정한 현재 시각
   * @return 활성 상태이고 시행 시각이 지나면 {@code true}
   */
  public boolean isEffectiveAt(LocalDateTime now) {
    return active && !effectiveAt.isAfter(now);
  }
}
