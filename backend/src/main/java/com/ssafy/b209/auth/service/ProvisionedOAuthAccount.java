package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AuthProvider;

/**
 * 검증된 OAuth 신원을 서비스 계정에 연결한 결과이다.
 *
 * @param userId 연결된 서비스 사용자 ID
 * @param provider OAuth Provider
 * @param newUser 이번 요청에서 사용자가 생성되었는지 여부
 * @param needsOnboarding 필수 역할과 프로필 입력이 필요한지 여부
 */
public record ProvisionedOAuthAccount(
    Long userId, AuthProvider provider, boolean newUser, boolean needsOnboarding) {}
