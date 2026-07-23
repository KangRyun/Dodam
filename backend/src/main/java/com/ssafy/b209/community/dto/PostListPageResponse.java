package com.ssafy.b209.community.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 공통 페이지 형식으로 게시글 목록과 페이지 메타데이터를 반환한다.
 *
 * @param content 현재 페이지의 게시글 목록
 * @param page 0부터 시작하는 현재 페이지
 * @param size 요청한 페이지 크기
 * @param totalElements 전체 조건 일치 건수
 * @param totalPages 전체 페이지 수
 * @param first 첫 페이지 여부
 * @param last 마지막 페이지 여부
 * @param hasNext 다음 페이지 존재 여부
 */
@Schema(description = "커뮤니티 게시글 목록 페이지")
public record PostListPageResponse(
    List<PostListItemResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last,
    boolean hasNext) {}
