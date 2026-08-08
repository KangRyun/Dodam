package com.ssafy.b209.report.service;

/**
 * 재시도 대기열에서 선점한 작업 한 건이다.
 *
 * @param id 재시도 작업 식별자
 * @param reportId 리포트 식별자
 * @param analysisId 최종 분석 식별자
 * @param attemptCount 이번 시도를 포함한 누적 시도 횟수
 * @param correlationId 최초 실패와 이 재시도를 잇는 식별자
 */
public record ReportGenerationRetry(
    long id, long reportId, long analysisId, int attemptCount, String correlationId) {}
