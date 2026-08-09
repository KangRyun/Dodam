package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

class CurrentAuthenticatedUserResolverTest {

  private final CurrentAuthenticatedUserResolver resolver = new CurrentAuthenticatedUserResolver();

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void returnsVerifiedAccessTokenSubject() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(41L), null, List.of()));

    assertThat(resolver.requireUserId()).isEqualTo(41L);
  }

  @Test
  void rejectsMissingPrincipal() {
    assertThatThrownBy(resolver::requireUserId)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.AUTHENTICATION_REQUIRED));
  }
}
