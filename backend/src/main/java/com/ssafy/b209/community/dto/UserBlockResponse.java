package com.ssafy.b209.community.dto;

/**
 * 현재 사용자의 차단 상태 응답이다.
 *
 * @param blockedUserId 차단 대상 사용자 ID
 * @param blocked 차단 여부
 */
public record UserBlockResponse(Long blockedUserId, boolean blocked) {}
