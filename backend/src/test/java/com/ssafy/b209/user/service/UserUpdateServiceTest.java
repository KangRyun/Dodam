package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.UpdateUserRequest;
import com.ssafy.b209.user.dto.response.NotificationSettingsResponse;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.exception.UserErrorCode;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserUpdateServiceTest {

  private static final Long USER_ID = 51L;
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-23T12:00:00Z"), ZoneOffset.UTC);

  @Mock private UserRepository userRepository;
  @Mock private UserNotificationSettingsReader notificationSettingsReader;

  private UserUpdateService service;

  @BeforeEach
  void setUp() {
    service = new UserUpdateService(userRepository, notificationSettingsReader, CLOCK);
  }

  @Test
  void updatesTheNicknameWhenProvided() {
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(onboardedUser()));
    given(notificationSettingsReader.read(USER_ID))
        .willReturn(NotificationSettingsResponse.defaults());

    UserResponse response = service.updateProfile(USER_ID, new UpdateUserRequest("새별이", null));

    verify(userRepository).save(any(User.class));
    assertThat(response.nickname()).isEqualTo("새별이");
    assertThat(response.notificationSettings()).isEqualTo(NotificationSettingsResponse.defaults());
  }

  @Test
  void leavesTheProfileUnchangedWhenNoFieldIsProvided() {
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(onboardedUser()));
    given(notificationSettingsReader.read(USER_ID))
        .willReturn(NotificationSettingsResponse.defaults());

    UserResponse response = service.updateProfile(USER_ID, new UpdateUserRequest(null, null));

    verify(userRepository, never()).save(any());
    assertThat(response.nickname()).isEqualTo("튼튼이엄마");
  }

  @Test
  void reportsUserNotFoundWhenTheUserIsMissing() {
    given(userRepository.findById(USER_ID)).willReturn(Optional.empty());

    assertThatThrownBy(() -> service.updateProfile(USER_ID, new UpdateUserRequest("새별이", null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(UserErrorCode.USER_NOT_FOUND));
  }

  private User onboardedUser() {
    User user = User.pending(LocalDateTime.of(2026, 7, 23, 0, 0));
    user.completeOnboarding(
        UserRole.GUARDIAN, "튼튼이엄마", "guardian@example.com", LocalDateTime.of(2026, 7, 23, 1, 0));
    return user;
  }
}
