package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.response.NotificationSettingsResponse;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.exception.UserErrorCode;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserQueryServiceTest {

  private static final Long USER_ID = 51L;

  @Mock private UserRepository userRepository;
  @Mock private UserNotificationSettingsReader notificationSettingsReader;

  private UserQueryService service;

  @BeforeEach
  void setUp() {
    service = new UserQueryService(userRepository, notificationSettingsReader);
  }

  @Test
  void returnsTheCurrentStateOfTheAuthenticatedUser() {
    User user = User.pending(LocalDateTime.of(2026, 7, 23, 0, 0));
    user.completeOnboarding(
        UserRole.GUARDIAN, "튼튼이엄마", "guardian@example.com", LocalDateTime.of(2026, 7, 23, 1, 0));
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(user));
    given(notificationSettingsReader.read(USER_ID))
        .willReturn(new NotificationSettingsResponse(true, false, true, false));

    UserResponse response = service.getMe(USER_ID);

    assertThat(response.role()).isEqualTo(UserRole.GUARDIAN);
    assertThat(response.nickname()).isEqualTo("튼튼이엄마");
    assertThat(response.email()).isEqualTo("guardian@example.com");
    assertThat(response.accountStatus()).isEqualTo(AccountStatus.ACTIVE);
    assertThat(response.onboardingCompleted()).isTrue();
    assertThat(response.notificationSettings())
        .isEqualTo(new NotificationSettingsResponse(true, false, true, false));
    assertThat(response.createdAt()).isEqualTo(Instant.parse("2026-07-23T00:00:00Z"));
    assertThat(response.lastLoginAt()).isNull();
    assertThat(response.profileImageUrl()).isNull();
  }

  @Test
  void reportsUserNotFoundWhenTheUserIsMissing() {
    given(userRepository.findById(USER_ID)).willReturn(Optional.empty());

    assertThatThrownBy(() -> service.getMe(USER_ID))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(UserErrorCode.USER_NOT_FOUND));
  }
}
