package com.ssafy.b209.user.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * PIN 변경 요청이다 (S15P11B209-879).
 *
 * <p>현재 PIN 을 함께 받는다. 현재 PIN 없이 바꿀 수 있으면 잠금이 무의미해진다.
 *
 * @param currentPin 현재 PIN
 * @param newPin 새 PIN
 */
@Schema(description = "보호자 PIN 변경 요청")
public record GuardianPinChangeRequest(
    @Schema(description = "현재 PIN", example = "1234") @NotBlank @Pattern(regexp = "^\\d{4}$")
        String currentPin,
    @Schema(description = "새 PIN", example = "5678") @NotBlank @Pattern(regexp = "^\\d{4}$")
        String newPin) {}
