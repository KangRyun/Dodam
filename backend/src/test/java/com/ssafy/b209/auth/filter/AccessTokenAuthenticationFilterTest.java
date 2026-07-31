package com.ssafy.b209.auth.filter;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.domain.AccountStatus;
import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.auth.token.JwtAccessTokenDecoder;
import jakarta.servlet.FilterChain;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.JwtException;

class AccessTokenAuthenticationFilterTest {

  private final JwtAccessTokenDecoder decoder = mock(JwtAccessTokenDecoder.class);
  private final AccessTokenAuthenticationFilter filter =
      new AccessTokenAuthenticationFilter(
          decoder, new ObjectMapper(), new AuthFilterProperties(false));

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void setsAuthenticatedUserOnlyWhileRequestChainRuns() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/v1/children/1");
    request.addHeader("Authorization", "Bearer signed-access-token");
    MockHttpServletResponse response = new MockHttpServletResponse();
    AuthenticatedUser principal = new AuthenticatedUser(41L);
    when(decoder.decode("signed-access-token")).thenReturn(principal);
    AtomicReference<Authentication> authenticationInChain = new AtomicReference<>();
    FilterChain chain =
        (ignoredRequest, ignoredResponse) ->
            authenticationInChain.set(SecurityContextHolder.getContext().getAuthentication());

    filter.doFilter(request, response, chain);

    assertThat(authenticationInChain.get().getPrincipal()).isEqualTo(principal);
    assertThat(authenticationInChain.get().getCredentials()).isNull();
    assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
  }

  @Test
  void rejectsInvalidBearerTokenWithSafeCommonErrorBody() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/v1/children/1");
    request.addHeader("Authorization", "Bearer invalid-token");
    MockHttpServletResponse response = new MockHttpServletResponse();
    FilterChain chain = mock(FilterChain.class);
    when(decoder.decode("invalid-token")).thenThrow(new JwtException("sensitive token detail"));

    filter.doFilter(request, response, chain);

    assertThat(response.getStatus()).isEqualTo(401);
    assertThat(response.getContentType()).startsWith("application/json");
    assertThat(response.getContentAsString()).contains("AUTH_401_002");
    assertThat(response.getContentAsString()).doesNotContain("sensitive token detail");
  }

  @Test
  void rejectsProtectedRequestWithoutAuthorization() throws Exception {
    MockHttpServletRequest request =
        new MockHttpServletRequest("GET", "/api/v1/drawing-sessions/active");
    MockHttpServletResponse response = new MockHttpServletResponse();
    FilterChain chain = mock(FilterChain.class);

    filter.doFilter(request, response, chain);

    assertThat(response.getStatus()).isEqualTo(401);
    assertThat(response.getContentAsString()).contains("AUTH_401_006");
  }

  @Test
  void allowsPublicOAuthRequestWithoutAuthorization() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/v1/auth/oauth/kakao");
    MockHttpServletResponse response = new MockHttpServletResponse();
    FilterChain chain = mock(FilterChain.class);

    filter.doFilter(request, response, chain);

    verify(chain).doFilter(request, response);
  }

  @Test
  void rejectsLogoutWithoutAccessToken() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/v1/auth/logout");
    MockHttpServletResponse response = new MockHttpServletResponse();
    FilterChain chain = mock(FilterChain.class);

    filter.doFilter(request, response, chain);

    assertThat(response.getStatus()).isEqualTo(401);
    assertThat(response.getContentAsString()).contains("AUTH_401_006");
  }

  @Test
  void testProfileCanTemporarilyBypassLegacyGuardianHeaders() throws Exception {
    AccessTokenAuthenticationFilter legacyFilter =
        new AccessTokenAuthenticationFilter(
            decoder, new ObjectMapper(), new AuthFilterProperties(true));
    MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/v1/children/1");
    request.addHeader("Authorization", "Bearer legacy-placeholder");
    request.addHeader("X-Guardian-User-Id", "10");
    MockHttpServletResponse response = new MockHttpServletResponse();
    FilterChain chain = mock(FilterChain.class);

    legacyFilter.doFilter(request, response, chain);

    verify(chain).doFilter(request, response);
  }

  @Test
  void rejectsAccessTokenForDeletedUser() throws Exception {
    UserRepository userRepository = mock(UserRepository.class);
    AccessTokenAuthenticationFilter stateAwareFilter =
        new AccessTokenAuthenticationFilter(
            decoder, new ObjectMapper(), new AuthFilterProperties(false), userRepository);
    MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/v1/users/me");
    request.addHeader("Authorization", "Bearer signed-access-token");
    MockHttpServletResponse response = new MockHttpServletResponse();
    FilterChain chain = mock(FilterChain.class);
    when(decoder.decode("signed-access-token")).thenReturn(new AuthenticatedUser(41L));
    User deletedUser = User.pending(java.time.LocalDateTime.of(2026, 7, 31, 1, 0));
    deletedUser.markDeleted(java.time.LocalDateTime.of(2026, 7, 31, 1, 1));
    when(userRepository.findById(41L)).thenReturn(Optional.of(deletedUser));

    stateAwareFilter.doFilter(request, response, chain);

    assertThat(deletedUser.getAccountStatus()).isEqualTo(AccountStatus.DELETED);
    assertThat(response.getStatus()).isEqualTo(403);
    assertThat(response.getContentAsString()).contains("AUTH_403_001");
  }
}
