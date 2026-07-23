package com.ssafy.b209.analysis.service;

/**
 * 분석 재시도 전에 보호자 접근 권한을 검증하는 데 필요한 최소 식별자다.
 *
 * @param analysisId 실패한 원본 분석 식별자
 * @param drawingSessionId 원본 분석이 속한 그림 활동 세션 식별자
 */
public record RetryDrawingAnalysisSource(Long analysisId, Long drawingSessionId) {}
