package com.ssafy.b209.report.service;

/**
 * 최종 분석이 리포트 완료로 전이됐을 때 보호자 알림·푸시 발송을 요청하는 도메인 이벤트다.
 *
 * <p>완료 저장 Transaction이 커밋된 뒤에 처리하도록 {@code AFTER_COMMIT} 단계에서만 소비한다. 발송 실패가 완료 처리를 되돌리지 않도록 알림 생성과
 * 발송은 완료 Transaction 밖에서 수행한다.
 *
 * @param reportId 완료된 리포트 식별자
 */
public record AnalysisCompletedEvent(Long reportId) {}
