package com.ssafy.b209.expert.domain;

import com.ssafy.b209.expert.dto.request.UploadExpertCredentialRequest;
import jakarta.persistence.CascadeType;
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
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/** 전문가 프로필에 속한 자격 정보와 검증 상태를 보관한다. */
@Entity
@Table(name = "expert_credentials")
public class ExpertCredential {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "expert_profile_id", nullable = false)
  private ExpertProfile expertProfile;

  @Column(name = "credential_type", nullable = false, length = 50)
  private String credentialType;

  @Column(name = "license_name", nullable = false, length = 150)
  private String credentialName;

  @Column(nullable = false, length = 150)
  private String issuer;

  @Column(name = "credential_number", length = 100)
  private String credentialNumberMasked;

  @Column(name = "acquired_on")
  private LocalDate issuedAt;

  @Enumerated(EnumType.STRING)
  @Column(name = "verification_status", nullable = false, length = 20)
  private ExpertVerificationStatus verificationStatus;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  @OneToMany(mappedBy = "expertCredential", cascade = CascadeType.ALL, orphanRemoval = true)
  private final List<ExpertCredentialFile> files = new ArrayList<>();

  protected ExpertCredential() {}

  /**
   * 업로드 요청을 검토 대기 자격으로 생성한다.
   *
   * @param profile 자격 소유 전문가 프로필
   * @param request 검토용 자격 Metadata
   * @param now 생성 시각
   * @return 파일이 아직 연결되지 않은 자격 Entity
   */
  public static ExpertCredential pending(
      ExpertProfile profile, UploadExpertCredentialRequest request, LocalDateTime now) {
    ExpertCredential credential = new ExpertCredential();
    credential.expertProfile = Objects.requireNonNull(profile);
    credential.credentialType = request.credentialType().trim();
    credential.credentialName = request.credentialName().trim();
    credential.issuer = request.issuer().trim();
    credential.credentialNumberMasked = normalizeOptional(request.credentialNumberMasked());
    credential.issuedAt = request.issuedAt();
    credential.verificationStatus = ExpertVerificationStatus.PENDING;
    credential.createdAt = Objects.requireNonNull(now);
    credential.updatedAt = now;
    return credential;
  }

  /** 자격 증빙 파일 하나를 현재 자격에 연결한다. */
  public void addFile(ExpertCredentialFile file) {
    files.add(Objects.requireNonNull(file));
  }

  public Long getId() {
    return id;
  }

  public String getCredentialType() {
    return credentialType;
  }

  public String getCredentialName() {
    return credentialName;
  }

  public String getIssuer() {
    return issuer;
  }

  public String getCredentialNumberMasked() {
    return credentialNumberMasked;
  }

  public LocalDate getIssuedAt() {
    return issuedAt;
  }

  public ExpertVerificationStatus getVerificationStatus() {
    return verificationStatus;
  }

  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  /**
   * 자격에 연결된 증빙 파일을 변경할 수 없는 목록으로 반환한다.
   *
   * @return 등록 순서의 증빙 파일 목록
   */
  public List<ExpertCredentialFile> getFiles() {
    return List.copyOf(files);
  }

  /**
   * 관리자 검토 결과를 자격에 반영한다.
   *
   * @param status 승인 또는 반려 상태
   * @param now 검토 완료 시각
   * @throws IllegalArgumentException 최종 상태가 아닌 값을 전달한 경우
   */
  public void completeVerification(ExpertVerificationStatus status, LocalDateTime now) {
    if (status != ExpertVerificationStatus.VERIFIED
        && status != ExpertVerificationStatus.REJECTED) {
      throw new IllegalArgumentException("final verification status is required");
    }
    verificationStatus = status;
    updatedAt = Objects.requireNonNull(now, "now must not be null");
  }

  private static String normalizeOptional(String value) {
    return value == null || value.isBlank() ? null : value.trim();
  }
}
