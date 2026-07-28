package com.ssafy.b209.user.dto.request;

import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.consent.dto.request.ConsentAgreementRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.Locale;

/**
 * 신규 사용자가 최초 정보를 등록하고 Onboarding을 완료하는 요청이다.
 *
 * <p>역할·닉네임·이메일은 필수이며, 약관 동의 결과를 함께 전달해 사용자 범위 필수 동의를 같은 요청에서 확정한다. {@code profileImageFileId}는 계약
 * 호환을 위해 받지만 현재 사전 업로드 이미지를 연결하는 기반이 없어 저장하지 않는다.
 *
 * @param role 사용자가 선택한 역할, {@code ADMIN}은 허용하지 않는다
 * @param nickname 사용자 표시 이름
 * @param email 사용자 연락 이메일
 * @param profileImageFileId 사전 업로드 프로필 이미지 식별자, 없으면 {@code null}
 * @param consents 필수·선택 약관 동의 결과
 */
public record OnboardingRequest(
    @NotNull UserRole role,
    @NotBlank @Size(max = 50) String nickname,
    @NotBlank @Email @Size(max = 255) String email,
    @Size(max = 255) String profileImageFileId,
    @NotNull @Valid List<ConsentAgreementRequest> consents) {

  /** 연락 이메일을 저장 형식으로 정규화하고 동의 결과 목록을 변경 불가능하게 복사한다. */
  public OnboardingRequest {
    if (email != null) {
      email = email.trim().toLowerCase(Locale.ROOT);
    }
    if (consents != null) {
      consents = List.copyOf(consents);
    }
  }
}
