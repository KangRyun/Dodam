package com.ssafy.b209.user.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.UserRole;
import java.time.Instant;

/**
 * 사용자 본인의 현재 상태를 반환한다.
 *
 * <p>Onboarding 완료 응답과 내 정보 조회, 프로필 수정 응답이 공유하는 표현이며 API 명세 6.3 {@code UserResponse}와 필드를 맞춘다.
 *
 * <p>{@code email}은 명세 6.3에 없지만 Provider가 이메일을 제공하지 않는 경우를 위해 Onboarding에서 확정하는 실제 저장 필드({@code
 * users.email})이므로 유지한다.
 *
 * @param userId 서비스 사용자 ID
 * @param role 확정된 사용자 역할, Onboarding 전이면 {@code null}
 * @param nickname 사용자 표시 이름, 입력 전이면 {@code null}
 * @param email 사용자 연락 이메일, 확정 전이면 {@code null}
 * @param accountStatus 계정 이용 상태
 * @param profileImageUrl 프로필 이미지 URL, 등록 전이면 {@code null}
 * @param notificationSettings 알림 수신 설정
 * @param onboardingCompleted 필수 사용자 정보 입력 완료 여부
 * @param lastLoginAt 마지막 로그인 시각, 기록이 없으면 {@code null}
 * @param createdAt 계정 생성 시각
 */
public record UserResponse(
    Long userId,
    UserRole role,
    String nickname,
    String email,
    AccountStatus accountStatus,
    String profileImageUrl,
    NotificationSettingsResponse notificationSettings,
    boolean onboardingCompleted,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant lastLoginAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant createdAt) {}
