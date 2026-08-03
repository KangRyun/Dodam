package com.ssafy.b209.community.dto;

import com.ssafy.b209.community.domain.ComplaintReasonCode;
import com.ssafy.b209.community.domain.ComplaintStatus;
import com.ssafy.b209.community.domain.ComplaintTargetType;
import java.time.Instant;

/**
 * 접수된 신고의 공개 식별 정보다. 신고자 정보는 대상 작성자에게 노출하지 않는다.
 *
 * @param complaintId 신고 ID
 * @param targetType 신고 대상 유형
 * @param targetId 신고 대상 ID
 * @param reasonCode 신고 사유
 * @param status 신고 처리 상태
 * @param createdAt 접수 UTC 시각
 */
public record ComplaintResponse(
    Long complaintId,
    ComplaintTargetType targetType,
    Long targetId,
    ComplaintReasonCode reasonCode,
    ComplaintStatus status,
    Instant createdAt) {}
