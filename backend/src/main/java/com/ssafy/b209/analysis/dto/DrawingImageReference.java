package com.ssafy.b209.analysis.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * 분석할 그림을 식별하는 내부 저장소 참조다.
 *
 * <p>{@code storageKey}는 절대 경로나 공개 URL이 아닌 불투명한 상대 Key다. 실제 이미지 전달 방식은 AI Client 계층에서 결정한다.
 *
 * @param storageKey 내부 이미지 저장소에서 사용하는 상대 Key
 * @param contentType 저장 단계에서 파일 Signature로 확인한 MIME Type
 */
public record DrawingImageReference(
    @NotBlank
        @Pattern(
            regexp = "^(?!/)(?!.*//)(?!.*(?:^|/)\\.{1,2}(?:/|$))(?!.*[/]$)[A-Za-z0-9._/-]+$",
            message = "storageKey는 안전한 상대 Key여야 합니다.")
        String storageKey,
    @NotBlank
        @Pattern(
            regexp = "image/(png|jpeg)",
            message = "contentType은 image/png 또는 image/jpeg여야 합니다.")
        String contentType) {}
