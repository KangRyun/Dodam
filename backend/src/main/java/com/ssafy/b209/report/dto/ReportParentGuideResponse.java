package com.ssafy.b209.report.dto;

import java.util.List;

/**
 * 유형별 보호자 가이드다 (875 §7).
 *
 * <p>{@code PROFESSIONAL_SUPPORT}는 상시 노출되는 일반 상담 안내이며 위기 문구·긴급 연락처를 담지 않는다 — 위기 안내는 {@code
 * crisisAlert}가 담당한다(계약 §4-4).
 *
 * @param guideType 가이드 유형
 * @param items 유형 안의 문장 목록
 */
public record ReportParentGuideResponse(String guideType, List<String> items) {}
