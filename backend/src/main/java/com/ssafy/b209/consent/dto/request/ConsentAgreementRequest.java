package com.ssafy.b209.consent.dto.request;

import com.ssafy.b209.consent.domain.ConsentAction;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * 고정 버전 약관 하나에 대한 사용자의 동의 행위다.
 *
 * @param termId 동의 화면에서 조회한 약관 ID
 * @param action 동의 또는 철회 의사 표시
 */
public record ConsentAgreementRequest(
    @NotNull @Positive Long termId, @NotNull ConsentAction action) {}
