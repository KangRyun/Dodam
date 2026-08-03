package com.ssafy.b209.expert.dto.request;

import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * 관리자가 전문가 프로필과 제출 자격의 승인 또는 반려 결과를 확정하는 요청이다.
 *
 * @param status 최종 상태인 {@code VERIFIED} 또는 {@code REJECTED}
 * @param verifiedCredentialIds 승인할 자격 ID 목록
 * @param rejectionReason 반려 시 전문가에게 공개할 사유
 * @param internalNote 관리자에게만 남기는 검토 메모
 */
public record ReviewExpertVerificationRequest(
    @NotNull ExpertVerificationStatus status,
    @NotNull @Size(max = 100) List<@Positive Long> verifiedCredentialIds,
    @Size(max = 1000) String rejectionReason,
    @Size(max = 2000) String internalNote) {}
