package com.ssafy.b209.user.service;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.user.dto.response.NotificationSettingsResponse;
import com.ssafy.b209.user.dto.response.UserResponse;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * 사용자 Entity를 사용자 응답으로 변환한다.
 *
 * <p>내 정보 조회, Onboarding 완료, 프로필 수정이 같은 매핑 규칙을 공유하도록 한곳에서 관리한다. 저장 시각은 {@code LocalDateTime}(UTC
 * 기준)이므로 API 계약의 ISO-8601 {@code Instant}로 변환해 노출한다.
 */
final class UserResponseMapper {

  private UserResponseMapper() {}

  /**
   * 사용자와 알림 설정을 사용자 응답으로 변환한다.
   *
   * @param user 조회·갱신된 사용자 Entity
   * @param notificationSettings 사용자 알림 수신 설정
   * @return API 명세 6.3과 필드를 맞춘 사용자 응답
   */
  static UserResponse toResponse(User user, NotificationSettingsResponse notificationSettings) {
    return new UserResponse(
        user.getId(),
        user.getRole(),
        user.getNickname(),
        user.getEmail(),
        user.getAccountStatus(),
        user.getProfileImageUrl(),
        notificationSettings,
        user.isOnboardingCompleted(),
        toInstant(user.getLastLoginAt()),
        toInstant(user.getCreatedAt()));
  }

  private static Instant toInstant(LocalDateTime value) {
    return value == null ? null : value.toInstant(ZoneOffset.UTC);
  }
}
