package com.ssafy.b209.community.repository;

import java.util.List;

/**
 * 게시글 Native Query의 목록 결과와 전체 건수를 함께 보관한다.
 *
 * @param content 현재 페이지의 Native Query 행
 * @param totalElements 조건에 맞는 전체 게시글 건수
 */
public record CommunityPostListPage(List<CommunityPostListRow> content, long totalElements) {}
