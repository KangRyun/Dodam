package com.ssafy.b209.user.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.user.dto.request.GuardianPinChangeRequest;
import com.ssafy.b209.user.dto.request.GuardianPinRequest;
import com.ssafy.b209.user.dto.response.GuardianPinStatusResponse;
import com.ssafy.b209.user.service.GuardianPinService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 보호자 PIN 설정·변경·검증·초기화 Endpoint다 (S15P11B209-879).
 *
 * <p>대상 사용자는 Access Token Principal 에서 해석한다. 경로에 사용자 식별자를 받지 않아 IDOR 을 구조로 차단한다.
 *
 * <p>응답은 성공·실패가 같은 구조체({@link GuardianPinStatusResponse})다. 실패도 남은 시도 횟수와 잠금 해제 시각을 함께 실어야 클라이언트가
 * 추가 조회 없이 화면을 만들 수 있다. PIN 원문·해시는 어떤 응답에도 포함하지 않는다.
 */
@Tag(name = "Guardian PIN", description = "아동 모드에서 보호자 화면으로 돌아올 때 요구하는 보호자 PIN")
@RestController
@RequestMapping("/api/v1/users/me/guardian-pin")
public class GuardianPinController {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final GuardianPinService guardianPinService;

  /**
   * 현재 사용자 Resolver와 PIN Use Case를 주입받는다.
   *
   * @param currentUserResolver Access Token Principal 기반 사용자 Resolver
   * @param guardianPinService 보호자 PIN Use Case
   */
  public GuardianPinController(
      CurrentAuthenticatedUserResolver currentUserResolver, GuardianPinService guardianPinService) {
    this.currentUserResolver = currentUserResolver;
    this.guardianPinService = guardianPinService;
  }

  /**
   * PIN 설정 여부와 잠금 상태를 조회한다.
   *
   * @return HTTP 200과 PIN 상태
   */
  @Operation(
      summary = "보호자 PIN 상태 조회",
      description = "PIN 설정 여부와 잠금 상태를 조회합니다. 클라이언트는 pinConfigured로 최초 설정 화면을 띄울지 판단합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "503",
        description = "PIN 기능 미구성(PIN_UNAVAILABLE)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<GuardianPinStatusResponse>> getGuardianPin() {
    return ResponseEntity.ok(
        ApiResponse.ok(guardianPinService.getStatus(currentUserResolver.requireUserId())));
  }

  /**
   * PIN 을 최초로 설정한다.
   *
   * @param request 숫자 4자리 PIN
   * @return HTTP 200과 설정 후 상태
   */
  @Operation(
      summary = "보호자 PIN 최초 설정",
      description =
          "PIN 을 처음 설정합니다. 이미 설정돼 있으면 409(PIN_ALREADY_CONFIGURED)입니다 — 변경은 현재 PIN 확인 경로로만 합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "설정 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "PIN 형식 오류(PIN_INVALID)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "이미 설정됨(PIN_ALREADY_CONFIGURED)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<GuardianPinStatusResponse>> configureGuardianPin(
      @Valid @RequestBody GuardianPinRequest request) {
    return ResponseEntity.ok(
        ApiResponse.ok(
            guardianPinService.configure(currentUserResolver.requireUserId(), request.pin())));
  }

  /**
   * 현재 PIN 을 확인하고 새 PIN 으로 바꾼다.
   *
   * @param request 현재 PIN과 새 PIN
   * @return HTTP 200과 변경 후 상태
   */
  @Operation(
      summary = "보호자 PIN 변경",
      description = "현재 PIN 을 확인한 뒤 새 PIN 으로 바꿉니다. 현재 PIN 이 틀리면 검증과 같은 실패·잠금 규칙을 적용합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "변경 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "현재 PIN 불일치(PIN_MISMATCH)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "설정된 PIN 없음(PIN_NOT_CONFIGURED)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "423",
        description = "잠금 중(PIN_LOCKED)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping
  public ResponseEntity<ApiResponse<GuardianPinStatusResponse>> changeGuardianPin(
      @Valid @RequestBody GuardianPinChangeRequest request) {
    return ResponseEntity.ok(
        ApiResponse.ok(
            guardianPinService.change(
                currentUserResolver.requireUserId(), request.currentPin(), request.newPin())));
  }

  /**
   * PIN 을 검증한다.
   *
   * <p>검증 성공은 단순 성공 응답이며 별도 해제 증표를 발급하지 않는다. 보호자 모드 해제 상태는 클라이언트가 메모리에서만 관리한다.
   *
   * @param request 입력 PIN
   * @return HTTP 200과 검증 후 상태
   */
  @Operation(
      summary = "보호자 PIN 검증",
      description =
          "아동 모드에서 보호자 화면으로 돌아올 때 PIN 을 검증합니다. "
              + "실패 응답에도 남은 시도 횟수와 잠금 해제 시각을 함께 실어 보냅니다. "
              + "성공 시 별도 해제 증표를 발급하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "검증 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "PIN 불일치(PIN_MISMATCH). data 에 남은 시도 횟수 포함",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "설정된 PIN 없음(PIN_NOT_CONFIGURED)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "423",
        description = "잠금 중(PIN_LOCKED). data 에 retryAfterSeconds·lockedUntil 포함",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/verifications")
  public ResponseEntity<ApiResponse<GuardianPinStatusResponse>> verifyGuardianPin(
      @Valid @RequestBody GuardianPinRequest request) {
    return ResponseEntity.ok(
        ApiResponse.ok(
            guardianPinService.verify(currentUserResolver.requireUserId(), request.pin())));
  }

  /**
   * PIN 을 초기화한다. 소셜 재인증 직후에만 허용한다.
   *
   * @return HTTP 200과 초기화 후 상태
   */
  @Operation(
      summary = "보호자 PIN 초기화",
      description =
          "PIN 분실 시 초기화합니다. 소셜 로그인으로 다시 인증한 직후에만 허용하며(최근 로그인 시각 기준), " + "단순 로그아웃만으로는 초기화되지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "초기화 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "소셜 재인증 필요(PIN_RESET_REQUIRED)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @DeleteMapping
  public ResponseEntity<ApiResponse<GuardianPinStatusResponse>> resetGuardianPin() {
    return ResponseEntity.ok(
        ApiResponse.ok(guardianPinService.reset(currentUserResolver.requireUserId())));
  }
}
