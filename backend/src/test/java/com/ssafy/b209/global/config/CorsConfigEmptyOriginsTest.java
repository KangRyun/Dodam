package com.ssafy.b209.global.config;

import static org.springframework.http.HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN;
import static org.springframework.http.HttpHeaders.ORIGIN;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@WebMvcTest(controllers = CorsConfigEmptyOriginsTest.EmptyOriginsController.class)
@ActiveProfiles("cors-empty")
@Import({CorsConfig.class, CorsConfigEmptyOriginsTest.EmptyOriginsController.class})
class CorsConfigEmptyOriginsTest {

  @Autowired private MockMvc mockMvc;

  @Test
  void rejectsCrossOriginRequestsWhenNoOriginsAreConfigured() throws Exception {
    mockMvc
        .perform(get("/api/v1/test/empty-origins").header(ORIGIN, "http://localhost:3000"))
        .andExpect(status().isForbidden())
        .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_ORIGIN));
  }

  @RestController
  static class EmptyOriginsController {

    @GetMapping("/api/v1/test/empty-origins")
    void cors() {}
  }
}
