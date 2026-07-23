package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.UserRole;

/**
 * OAuth 로그인 결과에 포함되는 최소 사용자 상태이다.
 *
 * @param userId 서비스 사용자 ID
 * @param role Onboarding 전이면 {@code null}, 완료 후 확정된 역할
 * @param nickname 입력 전이면 {@code null}, 이후 사용자 표시 이름
 * @param accountStatus 계정 이용 상태
 * @param onboardingCompleted 필수 사용자 정보 입력 완료 여부
 */
public record OAuthLoginUser(
    Long userId,
    UserRole role,
    String nickname,
    AccountStatus accountStatus,
    boolean onboardingCompleted) {}
