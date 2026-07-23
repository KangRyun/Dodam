package com.ssafy.b209.drawing.dto.response;

/**
 * 그림 활동 상세에서 보호자에게 공개할 아동의 최소 요약 정보다.
 *
 * @param childId 아동 식별자
 * @param nickname 아동 별칭
 */
public record DrawingSessionChildSummaryResponse(Long childId, String nickname) {}
