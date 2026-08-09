package com.ssafy.b209.drawing.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 보호자 활동 기록 목록과 페이지 메타데이터를 공통 페이지 형식으로 반환한다.
 *
 * @param content 정렬 기준이 적용된 현재 페이지 활동 기록 목록
 * @param page 0부터 시작하는 현재 페이지
 * @param size 요청한 페이지 크기
 * @param totalElements 조건에 맞는 전체 활동 기록 수
 * @param totalPages 전체 페이지 수
 * @param first 첫 페이지 여부
 * @param last 마지막 페이지 여부
 * @param hasNext 다음 페이지 존재 여부
 */
@Schema(description = "보호자 활동 기록 목록 페이지")
public record DrawingSessionHistoryPageResponse(
    List<DrawingSessionHistoryItemResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last,
    boolean hasNext) {

  /** 응답의 활동 기록 목록을 외부에서 변경할 수 없도록 복사한다. */
  public DrawingSessionHistoryPageResponse {
    content = List.copyOf(content);
  }
}
