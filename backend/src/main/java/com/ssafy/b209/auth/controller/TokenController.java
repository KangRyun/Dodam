package com.ssafy.b209.auth.controller;

import com.ssafy.b209.auth.dto.request.TokenReissueRequest;
import com.ssafy.b209.auth.service.OAuthLoginResult;
import com.ssafy.b209.auth.service.RefreshTokenService;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Refresh Token rotation을 통해 서비스 JWT를 재발급하는 HTTP API를 제공한다. */
@Tag(name = "Authentication", description = "OAuth 로그인 및 Token 재발급 API")
@RestController
@RequestMapping("/api/v1/auth")
public class TokenController {

  private final RefreshTokenService refreshTokenService;

  /**
   * Token 재발급 Controller를 구성한다.
   *
   * @param refreshTokenService Refresh Token 검증과 rotation을 수행하는 Service
   */
  public TokenController(RefreshTokenService refreshTokenService) {
    this.refreshTokenService = refreshTokenService;
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
  public ResponseEntity<ApiResponse<OAuthLoginResult>> reissue(
      @Valid @RequestBody TokenReissueRequest request) {
    return ResponseEntity.ok(ApiResponse.ok(refreshTokenService.reissue(request)));
  }
}
