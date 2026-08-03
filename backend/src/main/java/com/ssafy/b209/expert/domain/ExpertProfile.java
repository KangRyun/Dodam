package com.ssafy.b209.expert.domain;

import com.ssafy.b209.expert.dto.request.CreateExpertProfileRequest;
import com.ssafy.b209.expert.dto.request.UpdateExpertProfileRequest;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import org.hibernate.annotations.BatchSize;

/**
 * 전문가 사용자의 공개 프로필과 검증 상태를 관리한다.
 *
 * <p>사용자당 하나만 생성할 수 있으며, 전문 분야는 검색과 노출 순서를 위해 별도 행으로 소유한다. 자격 증빙과 관리자 검증은 후속 Use Case가 담당한다.
 */
@Entity
@Table(name = "expert_profiles")
public class ExpertProfile {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "user_id", nullable = false, unique = true)
  private Long userId;

  @Column(name = "display_name", nullable = false, length = 80)
  private String displayName;

  @Column(name = "profile_image_url", length = 1000)
  private String profileImageUrl;

  @Column(name = "organization", length = 150)
  private String organization;

  @Column(name = "position_title", length = 100)
  private String positionTitle;

  @Column(name = "career_years", nullable = false)
  private short careerYears;

  @Column(name = "target_age_min")
  private Short targetAgeMin;

  @Column(name = "target_age_max")
  private Short targetAgeMax;

  @Column(name = "introduction", columnDefinition = "text")
  private String introduction;

  @Column(name = "is_consultation_available", nullable = false)
  private boolean consultationAvailable;

  @Enumerated(EnumType.STRING)
  @Column(name = "verification_status", nullable = false, length = 20)
  private ExpertVerificationStatus verificationStatus;

  @Column(name = "workplace", length = 255)
  private String workplace;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  @OneToMany(mappedBy = "expertProfile", cascade = CascadeType.ALL, orphanRemoval = true)
  @OrderBy("displayOrder ASC")
  @BatchSize(size = 50)
  private final List<ExpertProfileSpecialty> specialties = new ArrayList<>();

  /** JPA가 Entity를 복원할 때 사용한다. */
  protected ExpertProfile() {}

  /**
   * 검토 대기 상태의 전문가 프로필을 생성한다.
   *
   * @param userId 전문가 역할 사용자 식별자
   * @param profileImageUrl 사용자 계정의 프로필 이미지 URL
   * @param request 검증을 마친 프로필 입력값
   * @param now 생성 시각
   * @return 전문 분야를 포함한 신규 프로필
   */
  public static ExpertProfile pending(
      Long userId, String profileImageUrl, CreateExpertProfileRequest request, LocalDateTime now) {
    ExpertProfile profile = new ExpertProfile();
    profile.userId = Objects.requireNonNull(userId, "userId must not be null");
    profile.displayName = normalizeRequired(request.displayName());
    profile.profileImageUrl = normalizeOptional(profileImageUrl);
    profile.organization = normalizeOptional(request.organization());
    profile.positionTitle = normalizeOptional(request.positionTitle());
    profile.careerYears = request.careerYears().shortValue();
    profile.targetAgeMin =
        request.targetAgeMin() == null ? null : request.targetAgeMin().shortValue();
    profile.targetAgeMax =
        request.targetAgeMax() == null ? null : request.targetAgeMax().shortValue();
    profile.introduction = normalizeOptional(request.introduction());
    profile.consultationAvailable = request.consultationAvailable();
    profile.verificationStatus = ExpertVerificationStatus.PENDING;
    profile.workplace = normalizeOptional(request.workplace());
    profile.createdAt = Objects.requireNonNull(now, "now must not be null");
    profile.updatedAt = now;
    for (int index = 0; index < request.specialties().size(); index++) {
      String code = request.specialties().get(index).trim();
      profile.specialties.add(ExpertProfileSpecialty.snapshot(profile, code, index, now));
    }
    return profile;
  }

  /**
   * @return 전문가 프로필 식별자
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 프로필을 소유한 사용자 식별자
   */
  public Long getUserId() {
    return userId;
  }

  /**
   * @return 사용자 계정의 프로필 이미지 URL
   */
  public String getProfileImageUrl() {
    return profileImageUrl;
  }

  /**
   * @return 공개 표시 이름
   */
  public String getDisplayName() {
    return displayName;
  }

  /**
   * @return 소속 기관
   */
  public String getOrganization() {
    return organization;
  }

  /**
   * @return 직책
   */
  public String getPositionTitle() {
    return positionTitle;
  }

  /**
   * @return 경력 연수
   */
  public int getCareerYears() {
    return careerYears;
  }

  /**
   * @return 상담 대상 최소 연령
   */
  public Integer getTargetAgeMin() {
    return targetAgeMin == null ? null : targetAgeMin.intValue();
  }

  /**
   * @return 상담 대상 최대 연령
   */
  public Integer getTargetAgeMax() {
    return targetAgeMax == null ? null : targetAgeMax.intValue();
  }

  /**
   * @return 공개 소개 문구
   */
  public String getIntroduction() {
    return introduction;
  }

  /**
   * @return 상담 가능 여부
   */
  public boolean isConsultationAvailable() {
    return consultationAvailable;
  }

  /**
   * @return 운영 검증 상태
   */
  public ExpertVerificationStatus getVerificationStatus() {
    return verificationStatus;
  }

  /**
   * @return 공개 근무지
   */
  public String getWorkplace() {
    return workplace;
  }

  /**
   * 전문 분야 코드를 노출 순서대로 반환한다.
   *
   * @return 수정할 수 없는 전문 분야 코드 목록
   */
  public List<String> getSpecialtyCodes() {
    return Collections.unmodifiableList(
        specialties.stream().map(ExpertProfileSpecialty::getSpecialtyCode).toList());
  }

  /**
   * 요청에 포함된 필드만 변경하고 자격 검토에 영향을 주는 변경이면 재검토 상태로 전이한다.
   *
   * <p>소개 문구와 상담 가능 여부는 운영 정보이므로 기존 검증 상태를 유지한다. 나머지 공개 자격 정보가 실제로 달라진 경우 {@link
   * ExpertVerificationStatus#REVIEW_REQUIRED}로 전환한다. 최초 검토 전인 {@link
   * ExpertVerificationStatus#PENDING} 상태는 그대로 유지한다.
   *
   * @param request 부분 수정 요청
   * @param now 수정 시각
   */
  public void update(UpdateExpertProfileRequest request, LocalDateTime now) {
    Objects.requireNonNull(request, "request must not be null");
    boolean reviewRequired = false;

    if (request.displayName() != null) {
      String value = normalizeRequired(request.displayName());
      reviewRequired |= !Objects.equals(displayName, value);
      displayName = value;
    }
    if (request.organization() != null) {
      String value = normalizeOptional(request.organization());
      reviewRequired |= !Objects.equals(organization, value);
      organization = value;
    }
    if (request.positionTitle() != null) {
      String value = normalizeOptional(request.positionTitle());
      reviewRequired |= !Objects.equals(positionTitle, value);
      positionTitle = value;
    }
    if (request.careerYears() != null) {
      short value = request.careerYears().shortValue();
      reviewRequired |= careerYears != value;
      careerYears = value;
    }
    if (request.targetAgeMin() != null) {
      short value = request.targetAgeMin().shortValue();
      reviewRequired |= !Objects.equals(targetAgeMin, value);
      targetAgeMin = value;
    }
    if (request.targetAgeMax() != null) {
      short value = request.targetAgeMax().shortValue();
      reviewRequired |= !Objects.equals(targetAgeMax, value);
      targetAgeMax = value;
    }
    if (request.workplace() != null) {
      String value = normalizeOptional(request.workplace());
      reviewRequired |= !Objects.equals(workplace, value);
      workplace = value;
    }
    if (request.specialties() != null) {
      List<String> values = request.specialties().stream().map(String::trim).toList();
      reviewRequired |= !getSpecialtyCodes().equals(values);
      var requestedCodes = new HashSet<>(values);
      specialties.removeIf(specialty -> !requestedCodes.contains(specialty.getSpecialtyCode()));
      for (int index = 0; index < values.size(); index++) {
        String code = values.get(index);
        ExpertProfileSpecialty existing =
            specialties.stream()
                .filter(specialty -> specialty.getSpecialtyCode().equals(code))
                .findFirst()
                .orElse(null);
        if (existing == null) {
          specialties.add(ExpertProfileSpecialty.snapshot(this, code, index, now));
        } else {
          existing.changeDisplayOrder(index);
        }
      }
      specialties.sort(Comparator.comparingInt(ExpertProfileSpecialty::getDisplayOrder));
    }
    if (request.introduction() != null) {
      introduction = normalizeOptional(request.introduction());
    }
    if (request.consultationAvailable() != null) {
      consultationAvailable = request.consultationAvailable();
    }
    if (reviewRequired && verificationStatus != ExpertVerificationStatus.PENDING) {
      verificationStatus = ExpertVerificationStatus.REVIEW_REQUIRED;
    }
    updatedAt = Objects.requireNonNull(now, "now must not be null");
  }

  /**
   * 자격 증빙이 추가되면 검토 완료 상태를 재검토 대상으로 전환한다.
   *
   * @param now 프로필 갱신 시각
   */
  public void requireCredentialReview(LocalDateTime now) {
    if (verificationStatus != ExpertVerificationStatus.PENDING) {
      verificationStatus = ExpertVerificationStatus.REVIEW_REQUIRED;
    }
    updatedAt = Objects.requireNonNull(now, "now must not be null");
  }

  /**
   * 관리자가 전문가 프로필의 최종 검증 상태를 확정한다.
   *
   * <p>검토 대기 상태를 표현하는 {@code PENDING}, {@code REVIEW_REQUIRED}는 이 메서드로 지정할 수 없다.
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

  private static String normalizeRequired(String value) {
    return Objects.requireNonNull(value, "value must not be null").trim();
  }

  private static String normalizeOptional(String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    return value.trim();
  }
}
