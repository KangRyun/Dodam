package com.ssafy.b209.report.dto;

import java.util.List;

/**
 * 보호자 리포트 목록과 페이지 메타데이터를 반환한다.
 *
 * @param content 현재 페이지의 리포트 목록
 * @param page 0부터 시작하는 현재 페이지
 * @param size 요청한 페이지 크기
 * @param totalElements 전체 리포트 수
 * @param totalPages 전체 페이지 수
 * @param first 첫 페이지 여부
 * @param last 마지막 페이지 여부
 * @param hasNext 다음 페이지 존재 여부
 */
public record ReportListPageResponse(
    List<ReportListItemResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last,
    boolean hasNext) {

  /** 응답 목록을 불변 복사본으로 보관한다. */
  public ReportListPageResponse {
    content = List.copyOf(content);
  }
}
