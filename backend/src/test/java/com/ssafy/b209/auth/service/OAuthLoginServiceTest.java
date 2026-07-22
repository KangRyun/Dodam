package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.token.IssuedTokenPair;
import com.ssafy.b209.auth.token.JwtTokenIssuer;
import com.ssafy.b209.global.exception.BusinessException;
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
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class OAuthLoginServiceTest {

  @Mock private OAuthProviderClient providerClient;
  @Mock private OAuthAccountProvisioningService provisioningService;
  @Mock private UserRepository userRepository;
  @Mock private JwtTokenIssuer tokenIssuer;

  private OAuthLoginService service;

  @BeforeEach
  void setUp() {
    service =
        new OAuthLoginService(
            providerClient,
            provisioningService,
            userRepository,
            tokenIssuer,
            Clock.fixed(Instant.parse("2026-07-22T12:00:00Z"), ZoneOffset.UTC));
  }

  @Test
  void exchangesCodeProvisionsAccountAndIssuesServiceTokens() {
    OAuthLoginRequest request =
        new OAuthLoginRequest(
            "one-time-code", "https://app.example/oauth/callback", null, "device-1");
    VerifiedOAuthIdentity identity =
        new VerifiedOAuthIdentity(AuthProvider.KAKAO, "kakao-id", null);
    User user = User.pending(LocalDateTime.of(2026, 7, 22, 11, 0));
    ReflectionTestUtils.setField(user, "id", 41L);
    when(providerClient.verify(AuthProvider.KAKAO, request)).thenReturn(identity);
    when(provisioningService.provision(identity))
        .thenReturn(new ProvisionedOAuthAccount(41L, AuthProvider.KAKAO, true, true));
    when(userRepository.findById(41L)).thenReturn(Optional.of(user));
    when(userRepository.save(user)).thenReturn(user);
    when(tokenIssuer.issue(41L))
        .thenReturn(new IssuedTokenPair("access", 1800, "refresh", 1209600));

    OAuthLoginResult result = service.login(AuthProvider.KAKAO, request);

    assertThat(result.accessToken()).isEqualTo("access");
    assertThat(result.refreshToken()).isEqualTo("refresh");
    assertThat(result.user().userId()).isEqualTo(41L);
    assertThat(result.user().accountStatus()).isEqualTo(AccountStatus.PENDING);
    assertThat(result.user().onboardingCompleted()).isFalse();
    verify(userRepository).findById(41L);
    verify(userRepository).save(user);
    verify(tokenIssuer).validateConfiguration();
    verify(tokenIssuer).issue(41L);
  }

  @Test
  void rejectsInvalidJwtConfigurationBeforeConsumingAuthorizationCode() {
    OAuthLoginRequest request =
        new OAuthLoginRequest("one-time-code", "https://app.example/google", null, "device-1");
    doThrow(new BusinessException(AuthErrorCode.AUTH_CONFIGURATION_INVALID))
        .when(tokenIssuer)
        .validateConfiguration();

    assertThatThrownBy(() -> service.login(AuthProvider.GOOGLE, request))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(providerClient, provisioningService, userRepository);
  }
}
