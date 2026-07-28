package com.ssafy.b209.report.dto;

/**
 * 리포트 목록에서 활동을 구분하는 그림 유형 요약이다.
 *
 * @param drawingTypeId 그림 유형 식별자
 * @param code 그림 유형 코드
 * @param name 보호자 화면에 표시할 그림 유형 이름
 */
public record ReportListDrawingTypeResponse(Long drawingTypeId, String code, String name) {}
