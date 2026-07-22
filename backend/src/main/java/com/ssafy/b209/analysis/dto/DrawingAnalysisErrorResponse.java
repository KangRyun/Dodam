package com.ssafy.b209.analysis.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * AI 그림 분석 실패를 안전하게 전달하는 오류 계약이다.
 *
 * <p>Stack Trace, 서버 경로 및 내부 Exception 정보는 포함하지 않는다.
 *
 * @param code 호출자가 분기 처리할 수 있는 안정적인 오류 코드
 * @param message 내부 구현 정보를 노출하지 않는 오류 설명
 */
public record DrawingAnalysisErrorResponse(@NotBlank String code, @NotBlank String message) {}
