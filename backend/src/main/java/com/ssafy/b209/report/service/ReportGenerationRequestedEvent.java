package com.ssafy.b209.report.service;

/**
 * 완료 접수가 리포트 껍데기를 만든 뒤 관찰 리포트 생성을 요청하는 도메인 이벤트다.
 *
 * <p>완료 Transaction이 커밋된 뒤에 처리하도록 {@code AFTER_COMMIT} 단계에서만 소비한다.
 *
 * @param analysisId 생성 대상 대기 중 최종 분석 식별자
 */
public record ReportGenerationRequestedEvent(Long analysisId) {}
