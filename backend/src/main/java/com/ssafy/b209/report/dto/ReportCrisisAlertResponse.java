package com.ssafy.b209.report.dto;

import java.util.List;

/**
 * 위기 대응 안내다 (875 §7-1).
 *
 * <p>{@code null}이 곧 "위기 신호 없음"이며 별도 플래그를 두지 않는다. 전부 사전 검토 템플릿이고 LLM 이 만들지 않는다.
 *
 * <p>{@code ABUSE_DISCLOSURE}는 이 값이 절대 생기지 않는다 — 가해자가 보호자일 수 있어 자동 통지가 아이를 위험하게 한다. 신호는 전문가 검토 필요
 * 표시로만 남는다.
 *
 * @param reasonCode 위기 사유 코드
 * @param severity 심각도({@code HIGH}·{@code ELEVATED})
 * @param title 안내 제목
 * @param message 안내 본문
 * @param actionSteps 보호자가 취할 행동 목록
 * @param resources 상담·신고 자원 목록
 */
public record ReportCrisisAlertResponse(
    String reasonCode,
    String severity,
    String title,
    String message,
    List<String> actionSteps,
    List<ReportCrisisResourceResponse> resources) {}
