package com.ssafy.b209.user.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.user.dto.request.OnboardingRequest;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.service.UserOnboardingService;
import com.ssafy.b209.user.service.UserQueryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 로그인 사용자의 본인 정보 HTTP API를 제공한다.
 *
 * <p>검증된 Access Token Principal로 요청자를 확인하며, 최초 정보 등록·온보딩 완료 규칙은 {@link UserOnboardingService}에
 * 위임한다.
 */
@Tag(name = "Users", description = "사용자 본인 정보 API")
@Validated
@RestController
@RequestMapping("/api/v1/users")
public class UserController {

  private static final int MAX_IP_LENGTH = 45;
  private static final int MAX_USER_AGENT_LENGTH = 500;

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final UserOnboardingService onboardingService;
  private final UserQueryService queryService;

  /**
   * 사용자 식별 경계와 조회·Onboarding 서비스를 사용하는 Controller를 생성한다.
   *
   * @param currentUserResolver Access Token Principal에서 사용자 식별자를 해석하는 경계
   * @param onboardingService 최초 정보 등록·온보딩 완료 Use Case
   * @param queryService 사용자 본인 정보 조회 Use Case
   */
  public UserController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      UserOnboardingService onboardingService,
      UserQueryService queryService) {
    this.currentUserResolver = currentUserResolver;
    this.onboardingService = onboardingService;
    this.queryService = queryService;
  }

  /**
   * 인증 사용자의 현재 계정 상태를 조회한다.
   *
   * <p>조회만 수행하며 계정 상태를 변경하지 않는다. Authorization Bearer Access Token의 사용자 ID를 대상으로 한다.
   *
   * @return HTTP 200과 사용자 본인 상태 공통 응답
   */
  @Operation(
      summary = "내 정보 조회",
      description =
          "인증 사용자의 현재 계정 상태를 조회합니다. 조회만으로 상태를 변경하지 않습니다. "
              + "Authorization Bearer Access Token의 사용자 ID를 대상으로 합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "내 정보 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "사용자를 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "서버 내부 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/me")
  public ResponseEntity<ApiResponse<UserResponse>> getMe() {
    return ResponseEntity.ok(
        ApiResponse.ok(queryService.getMe(currentUserResolver.requireUserId())));
  }

  /**
   * 인증 사용자의 최초 정보를 등록하고 Onboarding을 완료 처리한다.
   *
   * <p>역할·닉네임·이메일과 약관 동의 결과를 한 요청에서 저장하며, 이미 완료한 사용자가 다시 호출하면 현재 정보를 반환하는 멱등 동작이다. Authorization
   * Bearer Access Token의 사용자 ID를 대상으로 한다.
   *
   * @param request 등록할 사용자 정보와 약관 동의 결과
   * @param httpRequest 동의 증빙으로 기록할 원격 IP와 User-Agent를 제공하는 HTTP 요청
   * @return HTTP 200과 완료된 사용자 상태 공통 응답
   */
  @Operation(
      summary = "온보딩 완료",
      description =
          "신규 사용자의 역할·닉네임·이메일과 약관 동의 결과를 저장하고 온보딩을 완료합니다. "
              + "멱등한 PUT이며 이미 완료한 사용자는 현재 정보를 반환합니다. "
              + "Authorization Bearer Access Token의 사용자 ID를 대상으로 합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "온보딩 완료 또는 현재 정보 반환"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 오류 또는 허용되지 않는 역할",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "필수 약관 동의 누락",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "사용자 또는 약관을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "서버 내부 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PutMapping("/me/onboarding")
  public ResponseEntity<ApiResponse<UserResponse>> completeOnboarding(
      @Valid @RequestBody OnboardingRequest request, HttpServletRequest httpRequest) {
    UserResponse response =
        onboardingService.completeOnboarding(
            currentUserResolver.requireUserId(),
            request,
            limit(httpRequest.getRemoteAddr(), MAX_IP_LENGTH),
            limit(httpRequest.getHeader(HttpHeaders.USER_AGENT), MAX_USER_AGENT_LENGTH));
    return ResponseEntity.ok(ApiResponse.ok(response));
  }

  private String limit(String value, int maximumLength) {
    if (value == null || value.isBlank()) {
      return null;
    }
    return value.length() <= maximumLength ? value : value.substring(0, maximumLength);
  }
}
