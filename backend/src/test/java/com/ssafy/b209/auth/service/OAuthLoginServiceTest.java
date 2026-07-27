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
import com.ssafy.b209.auth.token.RefreshTokenHasher;
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
  @Mock private RefreshTokenSessionStore sessionStore;

  private OAuthLoginService service;

  @BeforeEach
  void setUp() {
    service =
        new OAuthLoginService(
            providerClient,
            provisioningService,
            userRepository,
            tokenIssuer,
            new RefreshTokenHasher(),
            sessionStore,
            Clock.fixed(Instant.parse("2026-07-22T12:00:00Z"), ZoneOffset.UTC));
  }

  @Test
  void verifiesKakaoAccessTokenProvisionsAccountAndIssuesServiceTokens() {
    OAuthLoginRequest request = new OAuthLoginRequest("kakao-access-token", null, null, "device-1");
    OAuthProviderCredential credential =
        new OAuthProviderCredential(OAuthCredentialType.ACCESS_TOKEN, "kakao-access-token");
    VerifiedOAuthIdentity identity =
        new VerifiedOAuthIdentity(AuthProvider.KAKAO, "kakao-id", null);
    User user = User.pending(LocalDateTime.of(2026, 7, 22, 11, 0));
    ReflectionTestUtils.setField(user, "id", 41L);
    when(providerClient.verify(AuthProvider.KAKAO, credential)).thenReturn(identity);
    when(provisioningService.provision(identity))
        .thenReturn(new ProvisionedOAuthAccount(41L, AuthProvider.KAKAO, null, true, true));
    when(userRepository.findById(41L)).thenReturn(Optional.of(user));
    when(userRepository.save(user)).thenReturn(user);
    when(tokenIssuer.issue(41L))
        .thenReturn(new IssuedTokenPair("access", 1800, "refresh", 1209600, "family-1"));

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
    verify(sessionStore)
        .register(
            "family-1",
            41L,
            "device-1",
            new RefreshTokenHasher().hash("refresh"),
            java.time.Duration.ofDays(14));
  }

  @Test
  void rejectsInvalidJwtConfigurationBeforeConsumingProviderToken() {
    OAuthLoginRequest request = new OAuthLoginRequest(null, "google-id-token", null, "device-1");
    doThrow(new BusinessException(AuthErrorCode.AUTH_CONFIGURATION_INVALID))
        .when(tokenIssuer)
        .validateConfiguration();

    assertThatThrownBy(() -> service.login(AuthProvider.GOOGLE, request))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(providerClient, provisioningService, userRepository);
  }

  @Test
  void rejectsGoogleAccessTokenBeforeCallingProvider() {
    OAuthLoginRequest request =
        new OAuthLoginRequest("google-access-token", null, null, "device-1");

    assertThatThrownBy(() -> service.login(AuthProvider.GOOGLE, request))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.OAUTH_REQUEST_INVALID));

    verifyNoInteractions(providerClient, provisioningService, userRepository);
  }

  @Test
  void rejectsBothProviderTokensBeforeCallingProvider() {
    OAuthLoginRequest request =
        new OAuthLoginRequest("kakao-access-token", "unexpected-id-token", null, "device-1");

    assertThatThrownBy(() -> service.login(AuthProvider.KAKAO, request))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.OAUTH_REQUEST_INVALID));

    verifyNoInteractions(providerClient, provisioningService, userRepository);
  }
}
