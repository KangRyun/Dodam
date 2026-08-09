package com.ssafy.b209.report.service;

/**
 * 리포트 생성이 <strong>되돌릴 수 없게</strong> 실패했을 때 보호자 알림·푸시 발송을 요청하는 도메인 이벤트다.
 *
 * <p><b>왜 필요한가.</b> 아이 화면은 리포트를 기다리지 않고 그냥 넘어간다. 그래서 리포트가 실패해도 아무 데도 표시되지 않는다 — 아이도 모르고, 보호자는 언젠가
 * 목록을 열어 봐야 안다. 알리지 않으면 실패가 조용히 묻힌다.
 *
 * <p><b>최종 실패만 싣는다.</b> {@code FAILED_RETRYABLE}은 재시도 작업이 되살릴 수 있고 보호자 화면에도 '분석 중'으로 보인다({@code
 * ReportStatus.visibleGroupOf}). 그 상태를 알리면 "만들지 못했어요" 뒤에 "완료됐어요"가 따라붙어, 보호자가 할 일이 없는데 불안만 남는다. 보호자가
 * 실제로 손을 써야 하는 {@code FAILED_FINAL}에서만 발행한다.
 *
 * <p>발송 실패가 실패 기록 자체를 되돌리지 않도록 알림 생성과 발송은 실패 기록 Transaction 밖에서 수행한다 — {@link
 * AnalysisCompletedEvent}와 같은 구조다.
 *
 * @param reportId 최종 실패한 리포트 식별자
 */
public record ReportGenerationFailedEvent(Long reportId) {}
