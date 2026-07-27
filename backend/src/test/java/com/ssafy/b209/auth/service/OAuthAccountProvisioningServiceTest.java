package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.domain.AuthAccount;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.AuthAccountRepository;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class OAuthAccountProvisioningServiceTest {

  private static final LocalDateTime NOW = LocalDateTime.of(2026, 7, 22, 12, 0);

  @Mock private UserRepository userRepository;
  @Mock private AuthAccountRepository authAccountRepository;

  private OAuthAccountProvisioningService service;

  @BeforeEach
  void setUp() {
    Clock clock = Clock.fixed(NOW.toInstant(ZoneOffset.UTC), ZoneOffset.UTC);
    service = new OAuthAccountProvisioningService(userRepository, authAccountRepository, clock);
  }

  @ParameterizedTest
  @EnumSource(AuthProvider.class)
  void provisionsEverySupportedProviderWithoutRequiringEmail(AuthProvider provider) {
    VerifiedOAuthIdentity identity = new VerifiedOAuthIdentity(provider, "provider-user", null);
    when(authAccountRepository.findByProviderAndProviderSubject(provider, "provider-user"))
        .thenReturn(Optional.empty());
    when(userRepository.save(any(User.class)))
        .thenAnswer(
            invocation -> {
              User user = invocation.getArgument(0);
              ReflectionTestUtils.setField(user, "id", 41L);
              return user;
            });
    when(authAccountRepository.saveAndFlush(any(AuthAccount.class)))
        .thenAnswer(invocation -> invocation.getArgument(0));

    ProvisionedOAuthAccount result = service.provision(identity);

    assertThat(result.userId()).isEqualTo(41L);
    assertThat(result.provider()).isEqualTo(provider);
    assertThat(result.providerEmail()).isNull();
    assertThat(result.newUser()).isTrue();
    assertThat(result.needsOnboarding()).isTrue();
    ArgumentCaptor<AuthAccount> accountCaptor = ArgumentCaptor.forClass(AuthAccount.class);
    verify(authAccountRepository).saveAndFlush(accountCaptor.capture());
    assertThat(accountCaptor.getValue().getProviderEmail()).isNull();
  }

  @Test
  void returnsStoredAppleEmailWhenRepeatedTokenOmitsEmail() {
    User user = User.pending(NOW);
    ReflectionTestUtils.setField(user, "id", 7L);
    AuthAccount account =
        AuthAccount.social(
            user,
            AuthProvider.APPLE,
            "apple-sub",
            "relay@privaterelay.appleid.com",
            NOW,
            NOW);
    when(authAccountRepository.findByProviderAndProviderSubject(
            AuthProvider.APPLE, "apple-sub"))
        .thenReturn(Optional.of(account));

    ProvisionedOAuthAccount result =
        service.provision(new VerifiedOAuthIdentity(AuthProvider.APPLE, "apple-sub", null));

    assertThat(result.userId()).isEqualTo(7L);
    assertThat(result.providerEmail()).isEqualTo("relay@privaterelay.appleid.com");
    assertThat(result.newUser()).isFalse();
    assertThat(result.needsOnboarding()).isTrue();
    verify(userRepository, never()).save(any());
    verify(authAccountRepository, never()).saveAndFlush(any());
  }

  @Test
  void recordsOnlyEmailThatWasVerifiedByProviderAdapter() {
    when(authAccountRepository.findByProviderAndProviderSubject(AuthProvider.GOOGLE, "google-sub"))
        .thenReturn(Optional.empty());
    when(userRepository.save(any(User.class)))
        .thenAnswer(
            invocation -> {
              User user = invocation.getArgument(0);
              ReflectionTestUtils.setField(user, "id", 9L);
              return user;
            });
    when(authAccountRepository.saveAndFlush(any(AuthAccount.class)))
        .thenAnswer(invocation -> invocation.getArgument(0));

    ProvisionedOAuthAccount result =
        service.provision(
            new VerifiedOAuthIdentity(AuthProvider.GOOGLE, "google-sub", "USER@EXAMPLE.COM"));

    assertThat(result.providerEmail()).isEqualTo("user@example.com");
    ArgumentCaptor<AuthAccount> accountCaptor = ArgumentCaptor.forClass(AuthAccount.class);
    verify(authAccountRepository).saveAndFlush(accountCaptor.capture());
    assertThat(accountCaptor.getValue().getProviderEmail()).isEqualTo("user@example.com");
    assertThat(accountCaptor.getValue().getProviderEmailVerifiedAt()).isEqualTo(NOW);
  }

  @Test
  void mapsConcurrentUniqueConflictToSafeBusinessError() {
    when(authAccountRepository.findByProviderAndProviderSubject(AuthProvider.NAVER, "naver-id"))
        .thenReturn(Optional.empty());
    when(userRepository.save(any(User.class)))
        .thenAnswer(
            invocation -> {
              User user = invocation.getArgument(0);
              ReflectionTestUtils.setField(user, "id", 11L);
              return user;
            });
    when(authAccountRepository.saveAndFlush(any(AuthAccount.class)))
        .thenThrow(new DataIntegrityViolationException("duplicate"));

    assertThatThrownBy(
            () ->
                service.provision(new VerifiedOAuthIdentity(AuthProvider.NAVER, "naver-id", null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.ACCOUNT_LINK_CONFLICT));
  }

  @Test
  void rejectsBlankProviderSubject() {
    assertThatThrownBy(
            () -> new VerifiedOAuthIdentity(AuthProvider.KAKAO, "  ", "user@example.com"))
        .isInstanceOf(IllegalArgumentException.class);
  }
}
