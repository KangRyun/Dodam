package com.ssafy.b209.user.dto.response;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.UserRole;

/**
 * 사용자 본인의 현재 상태를 반환한다.
 *
 * <p>Onboarding 완료 응답과 내 정보 조회에서 공유하는 표현이다. 프로필 이미지와 알림 설정은 별도 기능에서 제공한다.
 *
 * @param userId 서비스 사용자 ID
 * @param role 확정된 사용자 역할, Onboarding 전이면 {@code null}
 * @param nickname 사용자 표시 이름, 입력 전이면 {@code null}
 * @param email 사용자 연락 이메일, 확정 전이면 {@code null}
 * @param accountStatus 계정 이용 상태
 * @param onboardingCompleted 필수 사용자 정보 입력 완료 여부
 */
public record UserResponse(
    Long userId,
    UserRole role,
    String nickname,
    String email,
    AccountStatus accountStatus,
    boolean onboardingCompleted) {}
