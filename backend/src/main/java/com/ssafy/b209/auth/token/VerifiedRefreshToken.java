package com.ssafy.b209.auth.token;

/**
 * 서명과 표준 Claim 검증을 통과한 Refresh Token의 내부 식별 정보다.
 *
 * @param userId Token Subject에서 복원한 서비스 사용자 ID
 * @param familyId Redis rotation 세션을 찾는 family 식별자
 */
public record VerifiedRefreshToken(Long userId, String familyId) {}
