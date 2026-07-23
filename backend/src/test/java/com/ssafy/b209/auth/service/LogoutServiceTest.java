package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.dto.request.LogoutRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.token.JwtRefreshTokenDecoder;
import com.ssafy.b209.auth.token.RefreshTokenHasher;
import com.ssafy.b209.auth.token.VerifiedRefreshToken;
import com.ssafy.b209.global.exception.BusinessException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.RedisConnectionFailureException;

@ExtendWith(MockitoExtension.class)
class LogoutServiceTest {

  @Mock private JwtRefreshTokenDecoder tokenDecoder;
  @Mock private RefreshTokenSessionStore sessionStore;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;

  private final RefreshTokenHasher tokenHasher = new RefreshTokenHasher();
  private LogoutService service;

  @BeforeEach
  void setUp() {
    service = new LogoutService(tokenDecoder, tokenHasher, sessionStore, currentUserResolver);
  }

  @Test
  void revokesAuthenticatedUsersCurrentRefreshTokenFamily() {
    LogoutRequest request = new LogoutRequest("refresh-token", "device-1");
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(tokenDecoder.decode("refresh-token"))
        .thenReturn(new VerifiedRefreshToken(41L, "family-1"));
    when(sessionStore.revoke("family-1", 41L, "device-1", tokenHasher.hash("refresh-token")))
        .thenReturn(true);

    service.logout(request);

    verify(sessionStore).revoke("family-1", 41L, "device-1", tokenHasher.hash("refresh-token"));
  }

  @Test
  void rejectsRefreshTokenOwnedByAnotherUser() {
    LogoutRequest request = new LogoutRequest("refresh-token", "device-1");
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(tokenDecoder.decode("refresh-token"))
        .thenReturn(new VerifiedRefreshToken(99L, "family-1"));

    assertThatThrownBy(() -> service.logout(request))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.REFRESH_TOKEN_INVALID));
    verify(sessionStore, never())
        .revoke("family-1", 99L, "device-1", tokenHasher.hash("refresh-token"));
  }

  @Test
  void rejectsMissingOrMismatchedRefreshTokenSession() {
    LogoutRequest request = new LogoutRequest("refresh-token", "other-device");
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(tokenDecoder.decode("refresh-token"))
        .thenReturn(new VerifiedRefreshToken(41L, "family-1"));
    when(sessionStore.revoke("family-1", 41L, "other-device", tokenHasher.hash("refresh-token")))
        .thenReturn(false);

    assertThatThrownBy(() -> service.logout(request))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.REFRESH_TOKEN_INVALID));
  }

  @Test
  void failsClosedWhenRefreshSessionStoreIsUnavailable() {
    LogoutRequest request = new LogoutRequest("refresh-token", "device-1");
    when(currentUserResolver.requireUserId()).thenReturn(41L);
    when(tokenDecoder.decode("refresh-token"))
        .thenReturn(new VerifiedRefreshToken(41L, "family-1"));
    when(sessionStore.revoke("family-1", 41L, "device-1", tokenHasher.hash("refresh-token")))
        .thenThrow(new RedisConnectionFailureException("connection unavailable"));

    assertThatThrownBy(() -> service.logout(request))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.AUTH_SESSION_UNAVAILABLE));
  }
}
