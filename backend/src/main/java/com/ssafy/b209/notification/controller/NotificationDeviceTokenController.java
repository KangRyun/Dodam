package com.ssafy.b209.notification.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.notification.dto.request.RegisterDeviceTokenRequest;
import com.ssafy.b209.notification.dto.response.DeviceTokenResponse;
import com.ssafy.b209.notification.service.DeviceTokenService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * NOTI-01·NOTI-02 푸시 디바이스 Token HTTP API다.
 *
 * <p>Token 원문은 응답·로그에 남기지 않는다. 등록은 설치 식별자 기준 upsert이며 해제는 비활성화다.
 */
@Tag(name = "Notifications", description = "알림 API")
@RestController
@RequestMapping("/api/v1/notifications/device-tokens")
public class NotificationDeviceTokenController {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final DeviceTokenService deviceTokenService;

  /**
   * 인증 경계와 기기 Token Use Case를 연결한다.
   *
   * @param currentUserResolver 검증된 Access Token에서 사용자 ID를 해석하는 경계
   * @param deviceTokenService 기기 Token 등록·해제 Use Case
   */
  public NotificationDeviceTokenController(
      CurrentAuthenticatedUserResolver currentUserResolver, DeviceTokenService deviceTokenService) {
    this.currentUserResolver = currentUserResolver;
    this.deviceTokenService = deviceTokenService;
  }

  /**
   * 기기 Token을 등록하거나 같은 설치 식별자의 Token을 갱신한다.
   *
   * <p>같은 {@code deviceId} 재요청은 새 행을 만들지 않고 저장 값을 교체한다. 신규·갱신 모두 200을 반환하며 어느 쪽인지는 응답의 {@code
   * registered}로 구분한다. upsert라 Location을 제공하지 않는다.
   *
   * @param request 설치 식별자·Platform·Token·앱 버전이며 본문이 없으면 {@code null}
   * @return 저장 결과 공통 응답
   */
  @Operation(
      summary = "푸시 디바이스 Token 등록·갱신",
      description =
          "같은 deviceId는 갱신으로 처리합니다. Push Token은 봉인해 저장하며 응답에 포함하지 않습니다. "
              + "암호화 키가 구성되지 않은 환경에서는 503으로 거부합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "등록 또는 갱신 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 오류(DEVICE_TOKEN_INVALID)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "다른 계정에 이미 등록된 Token(DEVICE_TOKEN_ALREADY_REGISTERED)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "503",
        description = "Token 암호화 키 미구성(DEVICE_TOKEN_STORAGE_UNAVAILABLE)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<DeviceTokenResponse>> registerDeviceToken(
      @RequestBody(required = false) RegisterDeviceTokenRequest request) {
    Long userId = currentUserResolver.requireUserId();
    return ResponseEntity.ok(ApiResponse.ok(deviceTokenService.register(userId, request)));
  }

  /**
   * 설치 식별자로 기기 Token을 해제한다.
   *
   * <p>행을 삭제하지 않고 비활성화한다. 이미 비활성인 기기 재호출도 204로 처리해 로그아웃 재시도가 오류로 보이지 않게 한다.
   *
   * @param deviceId 해제할 설치 식별자
   * @return 본문이 없는 HTTP 204 응답
   */
  @Operation(
      summary = "푸시 디바이스 Token 해제",
      description = "설치 식별자에 해당하는 기기 Token을 비활성화합니다. 발송 대상에서 제외되며 기기 기록은 감사 목적으로 남습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "204",
        description = "해제 성공 또는 이미 해제됨"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "요청자에게 등록된 기기가 없음(DEVICE_TOKEN_NOT_FOUND)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @DeleteMapping("/{deviceId}")
  public ResponseEntity<Void> releaseDeviceToken(
      @Parameter(description = "해제할 설치 식별자", required = true) @PathVariable String deviceId) {
    Long userId = currentUserResolver.requireUserId();
    deviceTokenService.release(userId, deviceId);
    return ResponseEntity.noContent().build();
  }
}
