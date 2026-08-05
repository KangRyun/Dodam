package com.ssafy.b209.report.dto;

/**
 * 리포트 참고 자료 한 건이다 (875 §9).
 *
 * <p>{@code url}은 nullable 을 유지한다 — 자체 저작 자료는 URL 이 없다.
 *
 * @param title 자료 제목
 * @param url 자료 링크이며 없으면 {@code null}
 */
public record ReportReferenceResponse(String title, String url) {}
