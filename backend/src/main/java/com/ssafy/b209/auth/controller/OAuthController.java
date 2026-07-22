package com.ssafy.b209.auth.controller;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.service.OAuthLoginResult;
import com.ssafy.b209.auth.service.OAuthLoginService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirements;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.Locale;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Kakao·Google·Naver authorization code를 서비스 로그인 Token으로 교환하는 HTTP API를 제공한다. */
@Tag(name = "Authentication", description = "OAuth 로그인 API")
@RestController
@RequestMapping("/api/v1/auth")
public class OAuthController {

  private final OAuthLoginService loginService;

  /**
   * OAuth 로그인 Controller를 구성한다.
   *
   * @param loginService Provider 검증과 서비스 Token 발급을 수행하는 Service
   */
  public OAuthController(OAuthLoginService loginService) {
    this.loginService = loginService;
  }

  /**
   * Provider가 발급한 일회성 authorization code를 검증하고 서비스 JWT를 발급한다.
   *
   * @param provider Kakao, Google 또는 Naver를 나타내는 URI 값
   * @param request authorization code와 발급 시 사용한 Redirect URI
   * @return HTTP 200과 Access·Refresh Token 및 사용자 상태
   */
  @Operation(
      summary = "OAuth 로그인",
      description = "Kakao·Google·Naver authorization code를 Provider Token으로 교환하고 서비스 JWT를 발급합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "OAuth 로그인 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Provider, Redirect URI 또는 요청 형식 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "만료되었거나 유효하지 않은 authorization code",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "502",
        description = "OAuth Provider 통신 또는 응답 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/oauth/{provider}")
  @SecurityRequirements
  public ResponseEntity<ApiResponse<OAuthLoginResult>> login(
      @PathVariable String provider, @Valid @RequestBody OAuthLoginRequest request) {
    AuthProvider authProvider = parseProvider(provider);
    return ResponseEntity.ok(ApiResponse.ok(loginService.login(authProvider, request)));
  }

  private AuthProvider parseProvider(String provider) {
    try {
      return AuthProvider.valueOf(provider.toUpperCase(Locale.ROOT));
    } catch (IllegalArgumentException | NullPointerException exception) {
      throw new BusinessException(AuthErrorCode.OAUTH_REQUEST_INVALID, exception);
    }
  }
}
