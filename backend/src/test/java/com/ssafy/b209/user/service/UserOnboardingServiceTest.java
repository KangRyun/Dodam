package com.ssafy.b209.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.dto.request.ConsentAgreementRequest;
import com.ssafy.b209.consent.dto.request.CreateConsentRequest;
import com.ssafy.b209.consent.service.ConsentRegistrationService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.request.OnboardingRequest;
import com.ssafy.b209.user.dto.response.NotificationSettingsResponse;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.exception.UserErrorCode;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserOnboardingServiceTest {

  private static final Long USER_ID = 51L;
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-23T12:00:00Z"), ZoneOffset.UTC);

  @Mock private UserRepository userRepository;
  @Mock private ConsentRegistrationService consentRegistrationService;
  @Mock private UserNotificationSettingsReader notificationSettingsReader;

  private UserOnboardingService service;

  @BeforeEach
  void setUp() {
    service =
        new UserOnboardingService(
            userRepository, consentRegistrationService, notificationSettingsReader, CLOCK);
  }

  @Test
  void completesOnboardingRegistersConsentAndActivatesTheAccount() {
    User user = User.pending(LocalDateTime.of(2026, 7, 23, 0, 0));
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(user));
    given(notificationSettingsReader.read(USER_ID))
        .willReturn(NotificationSettingsResponse.defaults());
    List<ConsentAgreementRequest> consents =
        List.of(new ConsentAgreementRequest(1L, ConsentAction.AGREE));

    UserResponse response =
        service.completeOnboarding(USER_ID, request(consents), "203.0.113.7", "Flutter");

    verify(consentRegistrationService)
        .register(
            eq(USER_ID),
            eq(new CreateConsentRequest(null, consents)),
            eq("203.0.113.7"),
            eq("Flutter"));
    verify(userRepository).save(user);
    assertThat(response.role()).isEqualTo(UserRole.GUARDIAN);
    assertThat(response.nickname()).isEqualTo("튼튼이엄마");
    assertThat(response.email()).isEqualTo("guardian@example.com");
    assertThat(response.accountStatus()).isEqualTo(AccountStatus.ACTIVE);
    assertThat(response.onboardingCompleted()).isTrue();
  }

  @Test
  void normalizesContactEmailBeforeStoringOnboardingProfile() {
    User user = User.pending(LocalDateTime.of(2026, 7, 23, 0, 0));
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(user));
    given(notificationSettingsReader.read(USER_ID))
        .willReturn(NotificationSettingsResponse.defaults());
    OnboardingRequest request =
        new OnboardingRequest(
            UserRole.GUARDIAN,
            "보호자",
            "  Guardian@Example.COM  ",
            null,
            List.of(new ConsentAgreementRequest(1L, ConsentAction.AGREE)));

    UserResponse response = service.completeOnboarding(USER_ID, request, null, null);

    assertThat(response.email()).isEqualTo("guardian@example.com");
    assertThat(user.getEmail()).isEqualTo("guardian@example.com");
  }

  @Test
  void returnsCurrentStateWithoutSideEffectsWhenAlreadyOnboarded() {
    User user = User.pending(LocalDateTime.of(2026, 7, 23, 0, 0));
    user.completeOnboarding(
        UserRole.EXPERT, "이미완료", "done@example.com", LocalDateTime.of(2026, 7, 23, 1, 0));
    given(userRepository.findById(USER_ID)).willReturn(Optional.of(user));
    given(notificationSettingsReader.read(USER_ID))
        .willReturn(NotificationSettingsResponse.defaults());

    UserResponse response =
        service.completeOnboarding(
            USER_ID,
            request(List.of(new ConsentAgreementRequest(1L, ConsentAction.AGREE))),
            null,
            null);

    assertThat(response.onboardingCompleted()).isTrue();
    assertThat(response.role()).isEqualTo(UserRole.EXPERT);
    verify(consentRegistrationService, never()).register(any(), any(), any(), any());
    verify(userRepository, never()).save(any());
  }

  @Test
  void rejectsAdminRoleWithoutTouchingRepositories() {
    OnboardingRequest request =
        new OnboardingRequest(
            UserRole.ADMIN,
            "관리자",
            "admin@example.com",
            null,
            List.of(new ConsentAgreementRequest(1L, ConsentAction.AGREE)));

    assertThatThrownBy(() -> service.completeOnboarding(USER_ID, request, null, null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(UserErrorCode.ROLE_NOT_ALLOWED));
    verifyNoInteractions(userRepository, consentRegistrationService);
  }

  @Test
  void reportsUserNotFoundWhenTheAuthenticatedUserIsMissing() {
    given(userRepository.findById(USER_ID)).willReturn(Optional.empty());

    assertThatThrownBy(
            () ->
                service.completeOnboarding(
                    USER_ID,
                    request(List.of(new ConsentAgreementRequest(1L, ConsentAction.AGREE))),
                    null,
                    null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(UserErrorCode.USER_NOT_FOUND));
    verifyNoInteractions(consentRegistrationService);
  }

  private OnboardingRequest request(List<ConsentAgreementRequest> consents) {
    return new OnboardingRequest(
        UserRole.GUARDIAN, "튼튼이엄마", "guardian@example.com", null, consents);
  }
}
