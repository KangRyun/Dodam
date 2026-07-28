package com.ssafy.b209.user.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.user.dto.request.DeleteUserRequest;
import com.ssafy.b209.user.dto.request.NotificationSettingsUpdateRequest;
import com.ssafy.b209.user.dto.request.OnboardingRequest;
import com.ssafy.b209.user.dto.request.UpdateUserRequest;
import com.ssafy.b209.user.dto.response.NotificationSettingsResponse;
import com.ssafy.b209.user.dto.response.UserResponse;
import com.ssafy.b209.user.service.UserDeletionService;
import com.ssafy.b209.user.service.UserNotificationSettingsReader;
import com.ssafy.b209.user.service.UserNotificationSettingsUpdateService;
import com.ssafy.b209.user.service.UserOnboardingService;
import com.ssafy.b209.user.service.UserQueryService;
import com.ssafy.b209.user.service.UserUpdateService;
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
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
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
  private final UserUpdateService updateService;
  private final UserDeletionService deletionService;
  private final UserNotificationSettingsReader notificationSettingsReader;
  private final UserNotificationSettingsUpdateService notificationSettingsUpdateService;

  /**
   * 사용자 식별 경계와 조회·Onboarding·수정 서비스를 사용하는 Controller를 생성한다.
   *
   * @param currentUserResolver Access Token Principal에서 사용자 식별자를 해석하는 경계
   * @param onboardingService 최초 정보 등록·온보딩 완료 Use Case
   * @param queryService 사용자 본인 정보 조회 Use Case
   * @param updateService 사용자 본인 정보 수정 Use Case
   * @param deletionService 사용자 계정 즉시 삭제 Use Case
   * @param notificationSettingsReader 알림 수신 설정 조회 Use Case
   * @param notificationSettingsUpdateService 알림 수신 설정 변경 Use Case
   */
  public UserController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      UserOnboardingService onboardingService,
      UserQueryService queryService,
      UserUpdateService updateService,
      UserDeletionService deletionService,
      UserNotificationSettingsReader notificationSettingsReader,
      UserNotificationSettingsUpdateService notificationSettingsUpdateService) {
    this.currentUserResolver = currentUserResolver;
    this.onboardingService = onboardingService;
    this.queryService = queryService;
    this.updateService = updateService;
    this.deletionService = deletionService;
    this.notificationSettingsReader = notificationSettingsReader;
    this.notificationSettingsUpdateService = notificationSettingsUpdateService;
  }

  /**
   * 인증 사용자의 계정 식별정보를 즉시 삭제한다.
   *
   * @param request 탈퇴 확인 문자열
   * @return Body가 없는 HTTP 204 응답
   */
  @Operation(
      summary = "회원 탈퇴",
      description = "confirmation 값이 DELETE인 경우 인증 사용자의 계정 식별정보를 즉시 삭제합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "204",
        description = "회원 탈퇴 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "탈퇴 확인 값 불일치",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "사용자를 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @DeleteMapping("/me")
  public ResponseEntity<Void> deleteMe(@Valid @RequestBody DeleteUserRequest request) {
    deletionService.delete(currentUserResolver.requireUserId(), request);
    return ResponseEntity.noContent().build();
  }

  /**
   * 인증 사용자의 본인 프로필을 부분 수정한다.
   *
   * <p>전달한 필드만 변경하며 상태 변경은 하지 않는다. Authorization Bearer Access Token의 사용자 ID를 대상으로 한다.
   *
   * @param request 변경할 필드
   * @return HTTP 200과 수정 후 사용자 상태 공통 응답
   */
  @Operation(
      summary = "내 정보 수정",
      description =
          "인증 사용자의 닉네임 등 변경 가능한 프로필 필드를 부분 수정합니다. "
              + "전달한 필드만 반영하며 Authorization Bearer Access Token의 사용자 ID를 대상으로 합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "내 정보 수정 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "사용자를 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping("/me")
  public ResponseEntity<ApiResponse<UserResponse>> updateMe(
      @Valid @RequestBody UpdateUserRequest request) {
    return ResponseEntity.ok(
        ApiResponse.ok(updateService.updateProfile(currentUserResolver.requireUserId(), request)));
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
   * 인증 사용자의 알림 수신 설정을 조회한다.
   *
   * <p>조회만 수행하며 설정을 변경하지 않는다. 저장된 설정 행이 없는 사용자에게는 컬럼 DEFAULT와 동일한 기본값을 반환하므로 항상 HTTP 200이다.
   * Authorization Bearer Access Token의 사용자 ID를 대상으로 한다.
   *
   * @return HTTP 200과 알림 수신 설정 공통 응답
   */
  @Operation(
      summary = "알림 설정 조회",
      description =
          "인증 사용자의 알림 수신 설정을 조회합니다. 저장된 설정이 없으면 기본값을 반환하므로 항상 200으로 응답합니다. "
              + "Authorization Bearer Access Token의 사용자 ID를 대상으로 합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "알림 설정 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/me/notification-settings")
  public ResponseEntity<ApiResponse<NotificationSettingsResponse>> getMyNotificationSettings() {
    return ResponseEntity.ok(
        ApiResponse.ok(notificationSettingsReader.read(currentUserResolver.requireUserId())));
  }

  /**
   * 인증 사용자의 알림 수신 설정을 전체 교체한다.
   *
   * <p>부분 수정이 아니라 네 값을 모두 받는 전체 교체이므로 필드를 하나라도 누락하면 400이다. 저장된 설정 행이 없으면 새로 만들고 있으면 갱신하는 upsert이며,
   * 저장 후 최신 값을 반환한다. Authorization Bearer Access Token의 사용자 ID를 대상으로 한다.
   *
   * @param request 변경할 알림 수신 설정 네 값
   * @return HTTP 200과 수정 후 알림 수신 설정 공통 응답
   */
  @Operation(
      summary = "알림 설정 수정",
      description =
          "인증 사용자의 알림 수신 설정을 변경합니다. 네 값을 모두 전달하는 전체 교체이며 하나라도 누락하면 400을 반환합니다. "
              + "저장된 설정이 없으면 새로 만들고 있으면 갱신합니다. "
              + "Authorization Bearer Access Token의 사용자 ID를 대상으로 합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "알림 설정 수정 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 오류 또는 필수 필드 누락",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping("/me/notification-settings")
  public ResponseEntity<ApiResponse<NotificationSettingsResponse>> updateMyNotificationSettings(
      @Valid @RequestBody NotificationSettingsUpdateRequest request) {
    return ResponseEntity.ok(
        ApiResponse.ok(
            notificationSettingsUpdateService.update(
                currentUserResolver.requireUserId(), request)));
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
