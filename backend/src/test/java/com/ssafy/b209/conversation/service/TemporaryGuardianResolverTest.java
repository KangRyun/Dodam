package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.auth.filter.AuthFilterProperties;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

class TemporaryGuardianResolverTest {

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void resolvesUserIdFromVerifiedAccessTokenPrincipal() {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(41L), null, List.of()));
    TemporaryGuardianResolver resolver =
        new TemporaryGuardianResolver(new AuthFilterProperties(false));

    assertThat(resolver.resolve(null, null)).isEqualTo(41L);
  }

  @Test
  void rejectsLegacyHeadersWhenMigrationFlagIsDisabled() {
    TemporaryGuardianResolver resolver =
        new TemporaryGuardianResolver(new AuthFilterProperties(false));

    assertThatThrownBy(() -> resolver.resolve("Bearer placeholder", "10"))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.UNAUTHORIZED));
  }

  @Test
  void allowsLegacyHeadersOnlyForExplicitTestMigrationProfile() {
    TemporaryGuardianResolver resolver =
        new TemporaryGuardianResolver(new AuthFilterProperties(true));

    assertThat(resolver.resolve("Bearer placeholder", "10")).isEqualTo(10L);
  }
}
