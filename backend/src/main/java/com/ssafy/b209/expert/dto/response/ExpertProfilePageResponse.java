package com.ssafy.b209.expert.dto.response;

import java.util.List;

/**
 * 공개 전문가 목록과 페이지 정보를 반환한다.
 *
 * @param content 현재 페이지의 전문가 프로필
 * @param page 현재 페이지 번호
 * @param size 요청 페이지 크기
 * @param totalElements 전체 조건 일치 건수
 * @param totalPages 전체 페이지 수
 * @param hasNext 다음 페이지 존재 여부
 */
public record ExpertProfilePageResponse(
    List<ExpertProfileResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean hasNext) {

  /** 응답 목록을 외부에서 변경할 수 없도록 복사한다. */
  public ExpertProfilePageResponse {
    content = List.copyOf(content);
  }
}
