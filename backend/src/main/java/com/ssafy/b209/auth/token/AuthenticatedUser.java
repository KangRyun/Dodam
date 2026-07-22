package com.ssafy.b209.auth.token;

/**
 * 검증된 Access Token에서 복원한 서비스 사용자 Principal이다.
 *
 * @param userId Access Token Subject에 포함된 서비스 사용자 ID
 */
public record AuthenticatedUser(Long userId) {}
