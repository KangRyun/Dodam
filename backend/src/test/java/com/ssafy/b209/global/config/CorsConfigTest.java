package com.ssafy.b209.global.config;

import static org.hamcrest.Matchers.not;
import static org.springframework.http.HttpHeaders.ACCESS_CONTROL_ALLOW_CREDENTIALS;
import static org.springframework.http.HttpHeaders.ACCESS_CONTROL_ALLOW_HEADERS;
import static org.springframework.http.HttpHeaders.ACCESS_CONTROL_ALLOW_METHODS;
import static org.springframework.http.HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN;
import static org.springframework.http.HttpHeaders.ACCESS_CONTROL_MAX_AGE;
import static org.springframework.http.HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS;
import static org.springframework.http.HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD;
import static org.springframework.http.HttpHeaders.ORIGIN;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@WebMvcTest(
    controllers = CorsConfigTest.TestCorsController.class,
    properties = "app.cors.allowed-origins[0]=http://localhost:3000")
@Import({CorsConfig.class, CorsConfigTest.TestCorsController.class})
class CorsConfigTest {

  private static final String ALLOWED_METHODS = "GET,POST,PUT,PATCH,DELETE,OPTIONS";

  @Autowired private MockMvc mockMvc;

  @Test
  void allowsAnActualApiRequestFromAConfiguredOriginWithoutCredentials() throws Exception {
    mockMvc
        .perform(get("/api/v1/test/cors").header(ORIGIN, "http://localhost:3000"))
        .andExpect(status().isOk())
        .andExpect(header().string(ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:3000"))
        .andExpect(header().string(ACCESS_CONTROL_ALLOW_ORIGIN, not("*")))
        .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_CREDENTIALS));
  }

  @ParameterizedTest
  @ValueSource(strings = {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"})
  void allowsAConfiguredPreflightRequestForEachAllowedMethod(String requestMethod)
      throws Exception {
    mockMvc
        .perform(
            options("/api/v1/test/cors")
                .header(ORIGIN, "http://localhost:3000")
                .header(ACCESS_CONTROL_REQUEST_METHOD, requestMethod)
                .header(ACCESS_CONTROL_REQUEST_HEADERS, "Content-Type"))
        .andExpect(status().isOk())
        .andExpect(header().string(ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:3000"))
        .andExpect(header().string(ACCESS_CONTROL_ALLOW_METHODS, ALLOWED_METHODS))
        .andExpect(header().string(ACCESS_CONTROL_MAX_AGE, "3600"))
        .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_CREDENTIALS));
  }

  @ParameterizedTest
  @ValueSource(strings = {"Content-Type", "Accept", "Authorization"})
  void allowsAConfiguredPreflightRequestForEachAllowedHeader(String requestHeader)
      throws Exception {
    mockMvc
        .perform(
            options("/api/v1/test/cors")
                .header(ORIGIN, "http://localhost:3000")
                .header(ACCESS_CONTROL_REQUEST_METHOD, "GET")
                .header(ACCESS_CONTROL_REQUEST_HEADERS, requestHeader))
        .andExpect(status().isOk())
        .andExpect(header().string(ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:3000"))
        .andExpect(header().string(ACCESS_CONTROL_ALLOW_HEADERS, requestHeader))
        .andExpect(header().string(ACCESS_CONTROL_MAX_AGE, "3600"))
        .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_CREDENTIALS));
  }

  @Test
  void rejectsAPreflightRequestWithAnUnregisteredHeader() throws Exception {
    mockMvc
        .perform(
            options("/api/v1/test/cors")
                .header(ORIGIN, "http://localhost:3000")
                .header(ACCESS_CONTROL_REQUEST_METHOD, "GET")
                .header(ACCESS_CONTROL_REQUEST_HEADERS, "X-Not-Allowed"))
        .andExpect(status().isForbidden())
        .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_HEADERS));
  }

  @Test
  void rejectsAPreflightRequestFromAnUnconfiguredOrigin() throws Exception {
    mockMvc
        .perform(
            options("/api/v1/test/cors")
                .header(ORIGIN, "https://not-allowed.example")
                .header(ACCESS_CONTROL_REQUEST_METHOD, "GET"))
        .andExpect(status().isForbidden())
        .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_ORIGIN));
  }

  @Test
  void rejectsTracePreflightRequests() throws Exception {
    mockMvc
        .perform(
            options("/api/v1/test/cors")
                .header(ORIGIN, "http://localhost:3000")
                .header(ACCESS_CONTROL_REQUEST_METHOD, "TRACE"))
        .andExpect(status().isForbidden())
        .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_METHODS));
  }

  @Test
  void doesNotApplyCorsHeadersOutsideTheApiV1Mapping() throws Exception {
    mockMvc
        .perform(get("/outside/test/cors").header(ORIGIN, "http://localhost:3000"))
        .andExpect(status().isOk())
        .andExpect(header().doesNotExist(ACCESS_CONTROL_ALLOW_ORIGIN));
  }

  @RestController
  static class TestCorsController {

    @GetMapping({"/api/v1/test/cors", "/outside/test/cors"})
    void cors() {}
  }
}
