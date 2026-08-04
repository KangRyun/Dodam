package com.ssafy.b209.user.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * PIN 설정·검증 요청이다 (S15P11B209-879).
 *
 * <p>PIN 원문은 HTTPS 요청 본문으로만 받는다. 쿼리 파라미터로 받지 않는다 — URL 은 접근 로그·프록시·브라우저 이력에 남는다.
 *
 * @param pin 숫자 4자리 PIN
 */
@Schema(description = "보호자 PIN 요청")
public record GuardianPinRequest(
    @Schema(description = "숫자 4자리 PIN", example = "1234") @NotBlank @Pattern(regexp = "^\\d{4}$")
        String pin) {}
