package com.ssafy.b209.drawing.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 아동에게 노출할 그림 활동 유형과 공통 페이지 메타데이터를 반환한다.
 *
 * <p>그림 유형은 관리 데이터 규모가 작아 한 페이지로 반환하지만 Flutter의 공통 목록 계약을 유지하기 위해 페이지 메타데이터를 포함한다.
 *
 * @param content 노출 순서가 적용된 그림 유형 목록
 * @param page 0부터 시작하는 현재 페이지
 * @param size 현재 응답에 포함된 유형 수
 * @param totalElements 조건에 맞는 전체 유형 수
 * @param totalPages 결과가 있으면 1, 없으면 0
 * @param hasNext 다음 페이지 존재 여부
 */
@Schema(description = "그림 활동 유형 목록 페이지")
public record DrawingTypePageResponse(
    List<DrawingTypeResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean hasNext) {

  /** 응답 목록을 외부에서 변경할 수 없도록 복사한다. */
  public DrawingTypePageResponse {
    content = List.copyOf(content);
  }

  /**
   * 전체 그림 유형 목록을 단일 페이지 응답으로 변환한다.
   *
   * @param content 노출 순서가 적용된 그림 유형 목록
   * @return 공통 페이지 메타데이터를 포함한 단일 페이지
   */
  public static DrawingTypePageResponse singlePage(List<DrawingTypeResponse> content) {
    int size = content.size();
    return new DrawingTypePageResponse(content, 0, size, size, size == 0 ? 0 : 1, false);
  }
}
