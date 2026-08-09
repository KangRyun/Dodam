package com.ssafy.b209.community.dto;

import com.ssafy.b209.community.domain.ComplaintReasonCode;
import com.ssafy.b209.community.domain.ComplaintTargetType;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

/**
 * 통합 신고 생성 요청이다.
 *
 * @param targetType 신고 대상 유형
 * @param targetId 신고 대상 식별자
 * @param reasonCode 표준 신고 사유
 * @param description 신고 상세 설명
 */
public record ComplaintCreateRequest(
    @NotNull ComplaintTargetType targetType,
    @NotNull @Positive Long targetId,
    @NotNull ComplaintReasonCode reasonCode,
    @Size(max = 2000) String description) {}
