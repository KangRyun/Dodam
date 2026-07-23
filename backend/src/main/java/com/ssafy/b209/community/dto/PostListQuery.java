package com.ssafy.b209.community.dto;

/**
 * {@code GET /api/v1/posts}의 원시 Query Parameter를 보관한다.
 *
 * <p>모든 값은 Service에서 최신 공개 계약에 맞게 파싱·검증한다. 따라서 Spring의 Enum 자동 변환 오류 대신 일관된 {@code
 * VALIDATION_FAILED} 응답을 사용할 수 있다.
 *
 * @param postType 게시글 유형 문자열
 * @param page 0부터 시작하는 페이지 문자열
 * @param size 페이지 크기 문자열
 * @param sort 정렬 문자열
 */
public record PostListQuery(String postType, String page, String size, String sort) {}
