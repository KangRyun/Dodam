package com.ssafy.b209.consent.repository;

import java.util.List;

/**
 * 동의 이력 조회 결과와 전체 건수를 함께 전달한다.
 *
 * @param content 현재 페이지 이력
 * @param totalElements 조건에 맞는 전체 이력 수
 */
public record ConsentHistoryPage(List<ConsentHistoryRow> content, long totalElements) {}
