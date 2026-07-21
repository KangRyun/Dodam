package com.ssafy.b209.drawing.dto.response;

/**
 * 생성된 그림 활동 세션에 포함해 반환하는 그림 활동 유형의 요약 정보다.
 *
 * @param drawingTypeId 그림 활동 유형 식별자
 * @param code 그림 활동 유형 코드
 * @param name 그림 활동 유형 이름
 */
public record DrawingTypeSummaryResponse(Long drawingTypeId, String code, String name) {}
