package com.ssafy.b209.consent.domain;

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
import java.time.LocalDateTime;
import java.util.Objects;

/** 동의 또는 철회 행위를 덮어쓰지 않고 시점별로 보존하는 감사 이력이다. */
@Entity
@Table(name = "consent_records")
public class ConsentRecord {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "consent_term_id", nullable = false)
  private ConsentTerm consentTerm;

  @Column(name = "actor_user_id")
  private Long actorUserId;

  @Column(name = "subject_child_id")
  private Long subjectChildId;

  @Column(
      name = "subject_reference_hash",
      nullable = false,
      length = 64,
      columnDefinition = "char(64)")
  private String subjectReferenceHash;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 20)
  private ConsentAction action;

  @Column(name = "ip_address", length = 45)
  private String ipAddress;

  @Column(name = "user_agent", length = 500)
  private String userAgent;

  @Column(name = "recorded_at", nullable = false)
  private LocalDateTime recordedAt;

  /** JPA가 동의 이력을 복원할 때 사용한다. */
  protected ConsentRecord() {}

  private ConsentRecord(
      ConsentTerm consentTerm,
      Long actorUserId,
      Long subjectChildId,
      String subjectReferenceHash,
      ConsentAction action,
      String ipAddress,
      String userAgent,
      LocalDateTime recordedAt) {
    this.consentTerm = Objects.requireNonNull(consentTerm, "consentTerm must not be null");
    this.actorUserId = Objects.requireNonNull(actorUserId, "actorUserId must not be null");
    this.subjectChildId = subjectChildId;
    this.subjectReferenceHash =
        Objects.requireNonNull(subjectReferenceHash, "subjectReferenceHash must not be null");
    this.action = Objects.requireNonNull(action, "action must not be null");
    this.ipAddress = ipAddress;
    this.userAgent = userAgent;
    this.recordedAt = Objects.requireNonNull(recordedAt, "recordedAt must not be null");
  }

  /**
   * 현재 요청의 동의 행위를 새 감사 이력으로 생성한다.
   *
   * @param consentTerm 동의한 고정 버전 약관
   * @param actorUserId 동의를 처리한 인증 사용자 ID
   * @param subjectChildId 아동 약관의 대상 ID, 사용자 약관이면 {@code null}
   * @param subjectReferenceHash 사용자 또는 아동 대상을 나타내는 SHA-256 hash
   * @param action 동의 또는 철회
   * @param ipAddress 요청 원격 IP
   * @param userAgent 요청 User-Agent
   * @param recordedAt 서버 기록 시각
   * @return append할 동의 이력 Entity
   */
  public static ConsentRecord record(
      ConsentTerm consentTerm,
      Long actorUserId,
      Long subjectChildId,
      String subjectReferenceHash,
      ConsentAction action,
      String ipAddress,
      String userAgent,
      LocalDateTime recordedAt) {
    return new ConsentRecord(
        consentTerm,
        actorUserId,
        subjectChildId,
        subjectReferenceHash,
        action,
        ipAddress,
        userAgent,
        recordedAt);
  }

  /**
   * 저장된 동의 이력 식별자를 반환한다.
   *
   * @return 저장된 동의 이력 식별자
   */
  public Long getId() {
    return id;
  }
}
