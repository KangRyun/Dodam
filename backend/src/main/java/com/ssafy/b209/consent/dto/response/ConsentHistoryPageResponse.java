package com.ssafy.b209.consent.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 접근 가능한 동의 이력과 페이지 메타데이터를 반환한다.
 *
 * @param content 기록 시각 역순으로 정렬된 현재 페이지 이력
 * @param page 0부터 시작하는 현재 페이지
 * @param size 요청한 페이지 크기
 * @param totalElements 조건에 맞는 전체 이력 수
 * @param totalPages 전체 페이지 수
 * @param first 첫 페이지 여부
 * @param last 마지막 페이지 여부
 * @param hasNext 다음 페이지 존재 여부
 */
@Schema(description = "동의 이력 페이지")
public record ConsentHistoryPageResponse(
    List<ConsentHistoryItemResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last,
    boolean hasNext) {

  /** 응답 이력 목록을 외부에서 변경할 수 없도록 복사한다. */
  public ConsentHistoryPageResponse {
    content = List.copyOf(content);
  }
}
