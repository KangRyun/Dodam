package com.ssafy.b209.community.dto;

/**
 * 좋아요 등록 결과와 신규 생성 여부를 Controller에 전달한다.
 *
 * @param response 공개 응답
 * @param created 이번 요청에서 좋아요가 새로 생성됐으면 {@code true}
 */
public record PostLikeCommandResult(PostLikeResponse response, boolean created) {}
