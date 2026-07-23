package com.ssafy.b209.auth.controller;

import com.ssafy.b209.auth.dto.request.LogoutRequest;
import com.ssafy.b209.auth.dto.request.TokenReissueRequest;
import com.ssafy.b209.auth.service.LogoutService;
import com.ssafy.b209.auth.service.OAuthLoginResult;
import com.ssafy.b209.auth.service.RefreshTokenService;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirements;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Refresh Token rotation과 현재 기기 로그아웃을 제공하는 인증 HTTP API다. */
@Tag(name = "Authentication", description = "OAuth 로그인, Token 재발급 및 로그아웃 API")
@RestController
@RequestMapping("/api/v1/auth")
public class TokenController {

  private final RefreshTokenService refreshTokenService;
  private final LogoutService logoutService;

  /**
   * Token 재발급 Controller를 구성한다.
   *
   * @param refreshTokenService Refresh Token 검증과 rotation을 수행하는 Service
   * @param logoutService 현재 기기 Refresh Token 세션을 폐기하는 Service
   */
  public TokenController(RefreshTokenService refreshTokenService, LogoutService logoutService) {
    this.refreshTokenService = refreshTokenService;
    this.logoutService = logoutService;
  }

  /**
   * Refresh Token과 기기 정보를 확인하고 새 Access·Refresh Token을 발급한다.
   *
   * @param request 현재 Refresh Token과 기기 식별자
   * @return HTTP 200과 rotation된 Token pair 및 사용자 상태
   */
  @Operation(summary = "Token 재발급", description = "Refresh Token을 1회 사용하고 새 Token pair로 교체합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "Token 재발급 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Refresh Token 무효, 기기 불일치 또는 재사용 탐지",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "503",
        description = "인증 세션 저장소 장애",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/reissue")
  @SecurityRequirements
  public ResponseEntity<ApiResponse<OAuthLoginResult>> reissue(
      @Valid @RequestBody TokenReissueRequest request) {
    return ResponseEntity.ok(ApiResponse.ok(refreshTokenService.reissue(request)));
  }

  /**
   * 인증된 사용자의 현재 기기 Refresh Token 세션을 폐기한다.
   *
   * @param request 현재 기기의 Refresh Token과 기기 식별자
   * @return HTTP 200 공통 성공 응답
   */
  @Operation(
      summary = "현재 기기 로그아웃",
      description = "Access Token 사용자와 일치하는 현재 기기의 Refresh Token 세션을 폐기합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "로그아웃 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 형식 또는 필수 값 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 또는 Refresh Token이 유효하지 않음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "503",
        description = "인증 세션 저장소 장애",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/logout")
  public ResponseEntity<ApiResponse<Void>> logout(@Valid @RequestBody LogoutRequest request) {
    logoutService.logout(request);
    return ResponseEntity.ok(ApiResponse.ok());
  }
}
