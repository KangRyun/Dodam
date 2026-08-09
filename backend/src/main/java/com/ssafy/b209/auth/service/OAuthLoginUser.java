package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.UserRole;

/**
 * OAuth 로그인 결과에 포함되는 최소 사용자 상태이다.
 *
 * <p>{@code email}은 Provider가 검증 이메일을 제공했거나 Onboarding에서 확정한 경우 채워지며, {@code emailRequired}는 아직 사용할
 * 수 있는 이메일이 없어 Onboarding에서 수집해야 하는지를 프론트에 알린다. 프론트는 Provider 종류로 이메일 필요 여부를 판단하지 않는다.
 *
 * @param userId 서비스 사용자 ID
 * @param role Onboarding 전이면 {@code null}, 완료 후 확정된 역할
 * @param nickname 입력 전이면 {@code null}, 이후 사용자 표시 이름
 * @param email 확정된 사용자 이메일 또는 아직 없으면 {@code null}
 * @param emailRequired Onboarding에서 이메일을 수집해야 하면 {@code true}
 * @param accountStatus 계정 이용 상태
 * @param onboardingCompleted 필수 사용자 정보 입력 완료 여부
 */
public record OAuthLoginUser(
    Long userId,
    UserRole role,
    String nickname,
    String email,
    boolean emailRequired,
    AccountStatus accountStatus,
    boolean onboardingCompleted) {}
