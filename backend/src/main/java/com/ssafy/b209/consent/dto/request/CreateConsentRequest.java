package com.ssafy.b209.consent.dto.request;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * 사용자 또는 연결 아동의 최초 동의 이력을 일괄 등록하는 요청이다.
 *
 * @param childId 아동 대상 약관을 포함할 때의 연결 아동 ID, 사용자 약관만 처리하면 {@code null}
 * @param agreements 약관별 동의 행위 목록
 */
public record CreateConsentRequest(
    @Positive Long childId,
    @NotEmpty @Size(max = 100) List<@Valid ConsentAgreementRequest> agreements) {

  /** 외부 List 변경이 요청 의미를 바꾸지 않도록 불변 사본을 보관한다. */
  public CreateConsentRequest {
    if (agreements != null) {
      agreements = List.copyOf(agreements);
    }
  }
}
