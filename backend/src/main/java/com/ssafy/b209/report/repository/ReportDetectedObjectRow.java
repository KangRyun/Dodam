package com.ssafy.b209.report.repository;

/**
 * 그림 심리 상담 리포트가 노출할 탐지 객체 한 건과 그 출처를 담는 조회 결과다.
 *
 * <p>세션마다 최신 객체 탐지 분석 한 건만 남기는 판정을 Application 계층에서 하려면 어느 세션의 어느 분석에서 나온 이름인지가 함께 필요하다.
 *
 * @param drawingSessionId 탐지 결과가 속한 그림 활동 세션 식별자
 * @param analysisId 탐지 결과를 만든 객체 탐지 분석 식별자
 * @param objectName 탐지된 객체명이며 없으면 {@code null}
 * @param confidenceScore 탐지 신뢰도이며 없으면 {@code null}. 탐지 임계값은 0.20 으로 "박스를 남길지"의 기준일 뿐이라, 보호자에게 보이는
 *     값을 고를 때는 더 높은 기준으로 다시 걸러야 한다 (S15P11B209-912)
 */
public record ReportDetectedObjectRow(
    Long drawingSessionId,
    Long analysisId,
    String objectName,
    java.math.BigDecimal confidenceScore) {}
