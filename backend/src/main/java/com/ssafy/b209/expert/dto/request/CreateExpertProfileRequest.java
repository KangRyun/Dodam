package com.ssafy.b209.expert.dto.request;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.HashSet;
import java.util.List;

/**
 * 인증된 전문가가 공개 프로필을 최초 등록할 때 사용하는 요청이다.
 *
 * @param displayName 공개 표시 이름
 * @param organization 소속 기관
 * @param positionTitle 직책
 * @param careerYears 경력 연수
 * @param specialties 전문 분야 코드 목록
 * @param targetAgeMin 상담 대상 최소 연령
 * @param targetAgeMax 상담 대상 최대 연령
 * @param introduction 공개 소개 문구
 * @param consultationAvailable 상담 가능 여부
 * @param workplace 공개 근무지
 */
public record CreateExpertProfileRequest(
    @NotBlank @Size(max = 80) String displayName,
    @Size(max = 150) String organization,
    @Size(max = 100) String positionTitle,
    @NotNull @Min(0) @Max(80) Integer careerYears,
    @NotNull @Size(min = 1, max = 10)
        List<@NotBlank @Size(max = 50) @Pattern(regexp = "[A-Z][A-Z0-9_]*") String> specialties,
    @Min(0) @Max(19) Integer targetAgeMin,
    @Min(0) @Max(19) Integer targetAgeMax,
    @Size(max = 2000) String introduction,
    @NotNull Boolean consultationAvailable,
    @Size(max = 255) String workplace) {

  /**
   * 대상 연령이 함께 생략되거나 올바른 오름차순 범위인지 확인한다.
   *
   * @return 연령 범위가 일관되면 {@code true}
   */
  @AssertTrue(message = "targetAgeMin과 targetAgeMax는 함께 입력하고 최소 연령은 최대 연령 이하여야 합니다.")
  public boolean isTargetAgeRangeValid() {
    if (targetAgeMin == null || targetAgeMax == null) {
      return targetAgeMin == null && targetAgeMax == null;
    }
    return targetAgeMin <= targetAgeMax;
  }

  /**
   * 전문 분야 코드가 중복되지 않는지 확인한다.
   *
   * @return 모든 코드가 서로 다르면 {@code true}
   */
  @AssertTrue(message = "specialties에는 중복된 전문 분야 코드를 입력할 수 없습니다.")
  public boolean isSpecialtyCodesUnique() {
    if (specialties == null) {
      return true;
    }
    return new HashSet<>(specialties).size() == specialties.size();
  }
}
