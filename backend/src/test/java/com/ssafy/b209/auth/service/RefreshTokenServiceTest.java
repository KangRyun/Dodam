package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.dto.request.TokenReissueRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.token.IssuedTokenPair;
import com.ssafy.b209.auth.token.JwtRefreshTokenDecoder;
import com.ssafy.b209.auth.token.JwtTokenIssuer;
import com.ssafy.b209.auth.token.RefreshTokenHasher;
import com.ssafy.b209.auth.token.VerifiedRefreshToken;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class RefreshTokenServiceTest {

  @Mock private JwtRefreshTokenDecoder tokenDecoder;
  @Mock private JwtTokenIssuer tokenIssuer;
  @Mock private RefreshTokenSessionStore sessionStore;
  @Mock private UserRepository userRepository;

  private final RefreshTokenHasher tokenHasher = new RefreshTokenHasher();
  private RefreshTokenService service;

  @BeforeEach
  void setUp() {
    service =
        new RefreshTokenService(
            tokenDecoder, tokenIssuer, tokenHasher, sessionStore, userRepository);
  }

  @Test
  void rotatesCurrentRefreshTokenAndReturnsNewPair() {
    TokenReissueRequest request = new TokenReissueRequest("old-refresh", "device-1");
    User user = User.pending(LocalDateTime.of(2026, 7, 22, 12, 0));
    ReflectionTestUtils.setField(user, "id", 41L);
    when(tokenDecoder.decode("old-refresh")).thenReturn(new VerifiedRefreshToken(41L, "family-1"));
    when(userRepository.findById(41L)).thenReturn(Optional.of(user));
    when(tokenIssuer.issue(41L, "family-1"))
        .thenReturn(new IssuedTokenPair("new-access", 1800, "new-refresh", 1209600, "family-1"));
    when(sessionStore.rotate(
            "family-1",
            41L,
            "device-1",
            tokenHasher.hash("old-refresh"),
            tokenHasher.hash("new-refresh"),
            Duration.ofDays(14)))
        .thenReturn(RefreshTokenRotationResult.ROTATED);

    OAuthLoginResult result = service.reissue(request);

    assertThat(result.accessToken()).isEqualTo("new-access");
    assertThat(result.refreshToken()).isEqualTo("new-refresh");
    verify(sessionStore)
        .rotate(
            "family-1",
            41L,
            "device-1",
            tokenHasher.hash("old-refresh"),
            tokenHasher.hash("new-refresh"),
            Duration.ofDays(14));
  }

  @Test
  void revokesFamilyAndRejectsReusedRefreshToken() {
    TokenReissueRequest request = new TokenReissueRequest("old-refresh", "device-1");
    User user = User.pending(LocalDateTime.of(2026, 7, 22, 12, 0));
    ReflectionTestUtils.setField(user, "id", 41L);
    when(tokenDecoder.decode("old-refresh")).thenReturn(new VerifiedRefreshToken(41L, "family-1"));
    when(userRepository.findById(41L)).thenReturn(Optional.of(user));
    when(tokenIssuer.issue(41L, "family-1"))
        .thenReturn(new IssuedTokenPair("new-access", 1800, "new-refresh", 1209600, "family-1"));
    when(sessionStore.rotate(
            "family-1",
            41L,
            "device-1",
            tokenHasher.hash("old-refresh"),
            tokenHasher.hash("new-refresh"),
            Duration.ofDays(14)))
        .thenReturn(RefreshTokenRotationResult.REUSED);

    assertThatThrownBy(() -> service.reissue(request))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(AuthErrorCode.REFRESH_TOKEN_REUSED));
  }

  @Test
  void rejectsDifferentDeviceWithoutRotatingSession() {
    TokenReissueRequest request = new TokenReissueRequest("refresh", "other-device");
    User user = User.pending(LocalDateTime.of(2026, 7, 22, 12, 0));
    ReflectionTestUtils.setField(user, "id", 41L);
    when(tokenDecoder.decode("refresh")).thenReturn(new VerifiedRefreshToken(41L, "family-1"));
    when(userRepository.findById(41L)).thenReturn(Optional.of(user));
    when(tokenIssuer.issue(41L, "family-1"))
        .thenReturn(new IssuedTokenPair("access", 1800, "new-refresh", 1209600, "family-1"));
    when(sessionStore.rotate(
            "family-1",
            41L,
            "other-device",
            tokenHasher.hash("refresh"),
            tokenHasher.hash("new-refresh"),
            Duration.ofDays(14)))
        .thenReturn(RefreshTokenRotationResult.DEVICE_MISMATCH);

    assertThatThrownBy(() -> service.reissue(request))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.REFRESH_TOKEN_DEVICE_MISMATCH));
  }
}
