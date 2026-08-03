package com.ssafy.b209.community.dto;

/**
 * 차단 상태와 신규 생성 여부를 Controller에 전달한다.
 *
 * @param response 현재 차단 상태
 * @param created 이번 요청에서 차단 관계가 생성됐으면 {@code true}
 */
public record UserBlockCommandResult(UserBlockResponse response, boolean created) {}
