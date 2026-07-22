package com.ssafy.b209.consent.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.consent.dto.request.CreateConsentRequest;
import com.ssafy.b209.consent.dto.response.ConsentRegistrationResponse;
import com.ssafy.b209.consent.service.ConsentRegistrationService;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 인증 사용자 또는 연결 아동의 최초 약관 동의 이력을 등록하는 HTTP API를 제공한다. */
@Tag(name = "Consents", description = "사용자·아동 동의 관리 API")
@RestController
@RequestMapping("/api/v1/consents")
public class ConsentController {

  private static final int MAX_IP_LENGTH = 45;
  private static final int MAX_USER_AGENT_LENGTH = 500;

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ConsentRegistrationService registrationService;

  /**
   * 동의 등록 Controller를 구성한다.
   *
   * @param currentUserResolver Access Token 사용자 식별 경계
   * @param registrationService 최초 동의 검증·저장 Service
   */
  public ConsentController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ConsentRegistrationService registrationService) {
    this.currentUserResolver = currentUserResolver;
    this.registrationService = registrationService;
  }

  /**
   * 활성 필수 약관을 확인하고 동의·철회 행위를 새 이력으로 저장한다.
   *
   * @param request 아동 ID와 약관별 행위
   * @param httpRequest 원격 IP와 User-Agent 증빙을 제공하는 HTTP 요청
   * @return HTTP 201과 저장된 이력 수
   */
  @Operation(summary = "최초 동의 등록", description = "현재 활성 약관에 대한 동의 행위를 append-only 이력으로 저장합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "동의 이력 등록 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "중복 약관 또는 대상 범위 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "필수 동의 누락 또는 보호자 관계 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "약관을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "비활성 또는 시행 전 약관",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<ConsentRegistrationResponse>> register(
      @Valid @RequestBody CreateConsentRequest request, HttpServletRequest httpRequest) {
    ConsentRegistrationResponse response =
        registrationService.register(
            currentUserResolver.requireUserId(),
            request,
            limit(httpRequest.getRemoteAddr(), MAX_IP_LENGTH),
            limit(httpRequest.getHeader(HttpHeaders.USER_AGENT), MAX_USER_AGENT_LENGTH));
    return ResponseEntity.status(HttpStatus.CREATED)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }

  private String limit(String value, int maximumLength) {
    if (value == null || value.isBlank()) {
      return null;
    }
    return value.length() <= maximumLength ? value : value.substring(0, maximumLength);
  }
}
