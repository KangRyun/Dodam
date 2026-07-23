package com.ssafy.b209.auth.filter;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.auth.token.IssuedTokenPair;
import com.ssafy.b209.auth.token.JwtTokenIssuer;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(
    properties = {
      "app.auth.jwt.secret=0123456789abcdef0123456789abcdef",
      "app.auth.filter.legacy-header-enabled=false"
    })
@Import(AccessTokenFilterIntegrationTest.FilterProbeController.class)
class AccessTokenFilterIntegrationTest {

  @Autowired private MockMvc mockMvc;
  @Autowired private JwtTokenIssuer tokenIssuer;

  @Test
  void registeredFilterProvidesVerifiedPrincipalToApiController() throws Exception {
    String accessToken = tokenIssuer.issue(41L).accessToken();

    mockMvc
        .perform(get("/api/v1/filter-probe").header("Authorization", "Bearer " + accessToken))
        .andExpect(status().isOk())
        .andExpect(content().string("41"));
  }

  @Test
  void registeredFilterRejectsRefreshToken() throws Exception {
    IssuedTokenPair tokens = tokenIssuer.issue(41L);

    mockMvc
        .perform(
            get("/api/v1/filter-probe").header("Authorization", "Bearer " + tokens.refreshToken()))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_002"));
  }

  @Test
  void registeredFilterRejectsMissingAccessToken() throws Exception {
    mockMvc
        .perform(get("/api/v1/filter-probe"))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("AUTH_401_006"));
  }

  @RestController
  static class FilterProbeController {

    @GetMapping("/api/v1/filter-probe")
    String principalUserId() {
      Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
      AuthenticatedUser principal = (AuthenticatedUser) authentication.getPrincipal();
      return principal.userId().toString();
    }
  }
}
