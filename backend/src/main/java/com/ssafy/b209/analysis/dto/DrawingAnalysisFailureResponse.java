package com.ssafy.b209.analysis.dto;

/**
 * 실패로 종료된 그림 분석에서 Client에 공개할 수 있는 오류 정보를 나타낸다.
 *
 * @param code Client가 실패 결과를 식별할 수 있는 안정적인 오류 코드
 * @param message 내부 예외 정보를 포함하지 않는 사용자용 메시지
 */
public record DrawingAnalysisFailureResponse(String code, String message) {}
