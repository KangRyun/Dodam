package com.ssafy.b209.expert.dto.request;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.HashSet;
import java.util.List;
import java.util.stream.Stream;

/**
 * 인증된 전문가가 자신의 공개 프로필 일부를 수정할 때 사용하는 요청이다.
 *
 * <p>{@code null}인 필드는 기존 값을 유지한다. 선택 문자열 필드는 빈 문자열을 보내면 값을 삭제하며, 전문 분야 목록은 하나 이상의 코드가 필요하다.
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
public record UpdateExpertProfileRequest(
    @Size(max = 80) @Pattern(regexp = ".*\\S.*", message = "displayName은 공백일 수 없습니다.")
        String displayName,
    @Size(max = 150) String organization,
    @Size(max = 100) String positionTitle,
    @Min(0) @Max(80) Integer careerYears,
    @Size(min = 1, max = 10)
        List<@NotBlank @Size(max = 50) @Pattern(regexp = "[A-Z][A-Z0-9_]*") String> specialties,
    @Min(0) @Max(19) Integer targetAgeMin,
    @Min(0) @Max(19) Integer targetAgeMax,
    @Size(max = 2000) String introduction,
    Boolean consultationAvailable,
    @Size(max = 255) String workplace) {

  /**
   * 수정할 필드가 하나 이상 포함됐는지 확인한다.
   *
   * @return 적어도 한 필드가 전달됐으면 {@code true}
   */
  @AssertTrue(message = "수정할 전문가 프로필 필드를 하나 이상 입력해야 합니다.")
  public boolean isAnyFieldPresent() {
    return Stream.of(
            displayName,
            organization,
            positionTitle,
            careerYears,
            specialties,
            targetAgeMin,
            targetAgeMax,
            introduction,
            consultationAvailable,
            workplace)
        .anyMatch(java.util.Objects::nonNull);
  }

  /**
   * 전문 분야 코드가 중복되지 않는지 확인한다.
   *
   * @return 목록이 생략됐거나 모든 코드가 서로 다르면 {@code true}
   */
  @AssertTrue(message = "specialties에는 중복된 전문 분야 코드를 입력할 수 없습니다.")
  public boolean isSpecialtyCodesUnique() {
    return specialties == null || new HashSet<>(specialties).size() == specialties.size();
  }
}
