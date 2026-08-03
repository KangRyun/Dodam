package com.ssafy.b209.expert.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;

/**
 * 전문가 자격 증빙 파일과 함께 저장할 검토용 Metadata다.
 *
 * @param credentialType 자격 분류 코드
 * @param credentialName 자격명
 * @param issuer 발급 기관
 * @param issuedAt 취득일
 * @param credentialNumberMasked 노출 가능한 마스킹 자격 번호
 */
public record UploadExpertCredentialRequest(
    @NotBlank @Size(max = 50) @Pattern(regexp = "[A-Z][A-Z0-9_]*") String credentialType,
    @NotBlank @Size(max = 150) String credentialName,
    @NotBlank @Size(max = 150) String issuer,
    LocalDate issuedAt,
    @Size(max = 100) String credentialNumberMasked) {}
