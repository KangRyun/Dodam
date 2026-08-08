package com.ssafy.b209.screening.domain;

import com.ssafy.b209.child.domain.Child;
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
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * 보호자가 옮겨 적은 표준화 선별 결과 한 건이다.
 *
 * <p>이 서비스는 선별검사를 <strong>실시하지도 채점하지도 않는다.</strong> 보호자가 이미 다른 곳에서 받은 결과를 기록해 두고, 리포트에서 AI 관찰과 분리해
 * 보여 주기 위한 Entity다. 문항·채점키·규준표·절단점은 여기에 없고 앞으로도 들어오지 않는다.
 *
 * <p>{@code sourceVerified} 는 지금 언제나 {@code false} 다. 공식 서비스 연동이 없어 보호자 입력을 검증할 방법이 없기 때문이다.
 * <strong>검증되지 않은 값을 공식 결과처럼 보여 주는 것이 이 기능에서 가장 위험한 실패라</strong> 화면은 이 기록을 '보호자가 입력한 기록'으로만 보여 준다.
 *
 * <p>{@code payloadHash} 는 등록 당시 요청 본문의 해시다. 원본을 고정해 두어 값이 나중에 바뀌었는지 확인할 수 있게 한다.
 */
@Entity
@Table(name = "child_screening_records")
public class ChildScreeningRecord {

  /** 선별은 진단이 아니라는 고정 표기다. 다른 값이 들어갈 자리가 아니다. */
  public static final String DIAGNOSTIC_STATUS = "SCREENING_NOT_DIAGNOSIS";

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "child_id", nullable = false)
  private Child child;

  @Column(name = "instrument_id", nullable = false, length = 40)
  private String instrumentId;

  @Column(name = "instrument_version", length = 60)
  private String instrumentVersion;

  @Enumerated(EnumType.STRING)
  @Column(name = "respondent", nullable = false, length = 20)
  private ScreeningRespondent respondent;

  @Column(name = "completed_at", nullable = false)
  private LocalDate completedAt;

  @Column(name = "child_age_months_at_administration", columnDefinition = "SMALLINT")
  private Integer childAgeMonthsAtAdministration;

  @Enumerated(EnumType.STRING)
  @Column(name = "source_authority_type", nullable = false, length = 30)
  private ScreeningSourceAuthorityType sourceAuthorityType;

  @Column(name = "source_authority_name", nullable = false, length = 150)
  private String sourceAuthorityName;

  @Column(name = "source_verified", nullable = false)
  private boolean sourceVerified;

  @Column(name = "verification_method", length = 150)
  private String verificationMethod;

  @Column(name = "official_result_code", length = 60)
  private String officialResultCode;

  @Column(name = "official_result_text", nullable = false, length = 500)
  private String officialResultText;

  @Column(name = "diagnostic_status", nullable = false, length = 30)
  private String diagnosticStatus;

  @Column(name = "scored_by", nullable = false, length = 30)
  private String scoredBy;

  @Column(name = "ai_recalculated", nullable = false)
  private boolean aiRecalculated;

  @Enumerated(EnumType.STRING)
  @Column(name = "followup_level", length = 40)
  private ScreeningFollowupLevel followupLevel;

  @Column(name = "followup_message", length = 500)
  private String followupMessage;

  @Column(name = "consent_record_id", nullable = false)
  private Long consentRecordId;

  @Column(name = "source_document_ref", length = 300)
  private String sourceDocumentRef;

  @Column(name = "payload_hash", nullable = false, length = 64, columnDefinition = "char(64)")
  private String payloadHash;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "deleted_at")
  private LocalDateTime deletedAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ChildScreeningRecord() {}

  private ChildScreeningRecord(
      Child child,
      String instrumentId,
      String instrumentVersion,
      ScreeningRespondent respondent,
      LocalDate completedAt,
      Integer childAgeMonthsAtAdministration,
      ScreeningSourceAuthorityType sourceAuthorityType,
      String sourceAuthorityName,
      String officialResultCode,
      String officialResultText,
      String scoredBy,
      ScreeningFollowupLevel followupLevel,
      String followupMessage,
      Long consentRecordId,
      String sourceDocumentRef,
      String payloadHash,
      LocalDateTime createdAt) {
    this.child = Objects.requireNonNull(child, "child must not be null");
    this.instrumentId = Objects.requireNonNull(instrumentId, "instrumentId must not be null");
    this.instrumentVersion = instrumentVersion;
    this.respondent = Objects.requireNonNull(respondent, "respondent must not be null");
    this.completedAt = Objects.requireNonNull(completedAt, "completedAt must not be null");
    this.childAgeMonthsAtAdministration = childAgeMonthsAtAdministration;
    this.sourceAuthorityType =
        Objects.requireNonNull(sourceAuthorityType, "sourceAuthorityType must not be null");
    this.sourceAuthorityName =
        Objects.requireNonNull(sourceAuthorityName, "sourceAuthorityName must not be null");
    // 검증 주체가 없으므로 등록 시점에는 언제나 미검증이다. 호출부가 true 로 만들 수 없게 둔다.
    this.sourceVerified = false;
    this.verificationMethod = null;
    this.officialResultCode = officialResultCode;
    this.officialResultText =
        Objects.requireNonNull(officialResultText, "officialResultText must not be null");
    this.diagnosticStatus = DIAGNOSTIC_STATUS;
    this.scoredBy = Objects.requireNonNull(scoredBy, "scoredBy must not be null");
    this.aiRecalculated = false;
    this.followupLevel = followupLevel;
    this.followupMessage = followupMessage;
    this.consentRecordId =
        Objects.requireNonNull(consentRecordId, "consentRecordId must not be null");
    this.sourceDocumentRef = sourceDocumentRef;
    this.payloadHash = Objects.requireNonNull(payloadHash, "payloadHash must not be null");
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
  }

  /**
   * 보호자가 옮겨 적은 선별 결과를 만든다.
   *
   * <p>출처 검증 여부와 AI 재계산 여부는 <strong>인자로 받지 않는다.</strong> 둘 다 언제나 거짓이며, 호출부가 바꿀 수 있으면 언젠가 검증되지 않은
   * 기록이 공식 결과로 올라간다.
   *
   * @param child 대상 아동
   * @param instrumentId 등록부 allow-list 안의 도구 식별자
   * @param instrumentVersion 보호자가 적은 도구 버전이며 없으면 {@code null}
   * @param respondent 결과를 보고한 사람
   * @param completedAt 검사 실시일
   * @param childAgeMonthsAtAdministration 실시 당시 개월 나이이며 모르면 {@code null}
   * @param sourceAuthorityType 결과를 발급한 곳의 성격
   * @param sourceAuthorityName 결과를 발급한 곳
   * @param officialResultCode 공식 결과 코드이며 없으면 {@code null}
   * @param officialResultText 공식 결과 문구를 변경 없이
   * @param scoredBy 채점 주체이며 이 서비스는 절대 아니다
   * @param followupLevel 다음 걸음이며 적혀 있지 않으면 {@code null}
   * @param followupMessage 보호자에게 보이는 후속 안내이며 없으면 {@code null}
   * @param consentRecordId 확인된 임상 기록 보관 동의 이력
   * @param sourceDocumentRef 원본 문서 참조이며 없으면 {@code null}
   * @param payloadHash 등록 당시 요청 본문의 SHA-256
   * @param createdAt 등록 일시
   * @return 저장 대기 Entity
   */
  public static ChildScreeningRecord create(
      Child child,
      String instrumentId,
      String instrumentVersion,
      ScreeningRespondent respondent,
      LocalDate completedAt,
      Integer childAgeMonthsAtAdministration,
      ScreeningSourceAuthorityType sourceAuthorityType,
      String sourceAuthorityName,
      String officialResultCode,
      String officialResultText,
      String scoredBy,
      ScreeningFollowupLevel followupLevel,
      String followupMessage,
      Long consentRecordId,
      String sourceDocumentRef,
      String payloadHash,
      LocalDateTime createdAt) {
    return new ChildScreeningRecord(
        child,
        instrumentId,
        instrumentVersion,
        respondent,
        completedAt,
        childAgeMonthsAtAdministration,
        sourceAuthorityType,
        sourceAuthorityName,
        officialResultCode,
        officialResultText,
        scoredBy,
        followupLevel,
        followupMessage,
        consentRecordId,
        sourceDocumentRef,
        payloadHash,
        createdAt);
  }

  /**
   * 보호자의 삭제 요청을 기록한다. 행을 지우지 않고 시각을 남기는 이유는 동의 이력과 마찬가지로 <strong>무엇이 언제 사라졌는지</strong>가 감사 대상이기
   * 때문이다.
   *
   * @param deletedAt 삭제 시각
   */
  public void markDeleted(LocalDateTime deletedAt) {
    this.deletedAt = Objects.requireNonNull(deletedAt, "deletedAt must not be null");
  }

  /**
   * @return 이미 삭제된 기록이면 {@code true}
   */
  public boolean isDeleted() {
    return deletedAt != null;
  }

  /**
   * @return 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 도구 식별자
   */
  public String getInstrumentId() {
    return instrumentId;
  }

  /**
   * @return 도구 버전
   */
  public String getInstrumentVersion() {
    return instrumentVersion;
  }

  /**
   * @return 응답자
   */
  public ScreeningRespondent getRespondent() {
    return respondent;
  }

  /**
   * @return 검사 실시일
   */
  public LocalDate getCompletedAt() {
    return completedAt;
  }

  /**
   * @return 실시 당시 개월 나이
   */
  public Integer getChildAgeMonthsAtAdministration() {
    return childAgeMonthsAtAdministration;
  }

  /**
   * @return 결과를 발급한 곳의 성격
   */
  public ScreeningSourceAuthorityType getSourceAuthorityType() {
    return sourceAuthorityType;
  }

  /**
   * @return 결과를 발급한 곳
   */
  public String getSourceAuthorityName() {
    return sourceAuthorityName;
  }

  /**
   * @return 출처가 검증됐으면 {@code true}. 검증 주체가 없어 현재 언제나 {@code false}
   */
  public boolean isSourceVerified() {
    return sourceVerified;
  }

  /**
   * @return 검증 방법
   */
  public String getVerificationMethod() {
    return verificationMethod;
  }

  /**
   * @return 공식 결과 코드
   */
  public String getOfficialResultCode() {
    return officialResultCode;
  }

  /**
   * @return 공식 결과 문구
   */
  public String getOfficialResultText() {
    return officialResultText;
  }

  /**
   * @return 선별은 진단이 아니라는 고정 표기
   */
  public String getDiagnosticStatus() {
    return diagnosticStatus;
  }

  /**
   * @return 채점 주체
   */
  public String getScoredBy() {
    return scoredBy;
  }

  /**
   * @return AI 재계산 여부이며 언제나 {@code false}
   */
  public boolean isAiRecalculated() {
    return aiRecalculated;
  }

  /**
   * @return 다음 걸음
   */
  public ScreeningFollowupLevel getFollowupLevel() {
    return followupLevel;
  }

  /**
   * @return 후속 안내
   */
  public String getFollowupMessage() {
    return followupMessage;
  }

  /**
   * @return 확인된 동의 이력 식별자
   */
  public Long getConsentRecordId() {
    return consentRecordId;
  }

  /**
   * @return 원본 문서 참조
   */
  public String getSourceDocumentRef() {
    return sourceDocumentRef;
  }

  /**
   * @return 등록 당시 요청 본문 해시
   */
  public String getPayloadHash() {
    return payloadHash;
  }

  /**
   * @return 등록 일시
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  /**
   * @return 삭제 일시이며 살아 있으면 {@code null}
   */
  public LocalDateTime getDeletedAt() {
    return deletedAt;
  }
}
