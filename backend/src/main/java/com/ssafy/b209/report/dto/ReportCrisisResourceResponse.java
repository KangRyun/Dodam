package com.ssafy.b209.report.dto;

/**
 * 위기 안내에 함께 싣는 상담·신고 자원이다 (875 §7-1).
 *
 * @param name 자원 이름
 * @param contact 연락처
 * @param note 보충 설명이며 없으면 빈 문자열
 */
public record ReportCrisisResourceResponse(String name, String contact, String note) {}
