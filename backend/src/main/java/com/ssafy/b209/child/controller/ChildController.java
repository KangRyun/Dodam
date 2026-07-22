package com.ssafy.b209.child.controller;

import com.ssafy.b209.child.dto.response.ChildDetailResponse;
import com.ssafy.b209.child.service.ChildQueryService;
import com.ssafy.b209.conversation.service.TemporaryGuardianResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Positive;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 보호자가 이용하는 아동 프로필 HTTP API를 제공한다.
 *
 * <p>검증된 Access Token Principal로 요청자를 확인하며, 상세 조회 규칙과 소유권 검증은 {@link ChildQueryService}에 위임한다.
 */
@Tag(name = "Children", description = "아동 프로필 API")
@Validated
@RestController
@RequestMapping("/api/v1/children")
public class ChildController {

  private final TemporaryGuardianResolver guardianResolver;
  private final ChildQueryService childQueryService;

  /**
   * 보호자 식별 경계와 아동 상세 조회 서비스를 사용하는 Controller를 생성한다.
   *
   * @param guardianResolver Access Token Principal에서 보호자 식별자를 해석하는 경계
   * @param childQueryService 아동 상세 조회 Use Case
   */
  public ChildController(
      TemporaryGuardianResolver guardianResolver, ChildQueryService childQueryService) {
    this.guardianResolver = guardianResolver;
    this.childQueryService = childQueryService;
  }

  /**
   * 요청 보호자에게 연결된 활성 아동의 상세 프로필을 조회한다.
   *
   * <p>조회만 수행하며 아동 프로필이나 보호자 관계의 상태를 변경하지 않는다.
   *
   * @param childId 조회할 아동 식별자
   * @param authorization Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @param guardianUserId Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @return HTTP 200과 아동 상세 프로필 공통 응답
   */
  @Operation(
      summary = "아동 정보 조회",
      description =
          "요청 보호자에게 연결된 활성 아동의 상세 프로필을 조회합니다. "
              + "조회만으로 아동이나 관계 상태를 변경하지 않습니다. "
              + "Authorization Bearer Access Token의 사용자 ID로 보호자 관계를 검증합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "아동 정보 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "아동 식별자 형식 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "아동이 없거나 삭제됐거나 요청 보호자에게 연결되지 않음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "서버 내부 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{childId}")
  public ResponseEntity<ApiResponse<ChildDetailResponse>> getChild(
      @Parameter(description = "조회할 아동 식별자", required = true) @PathVariable @Positive Long childId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long resolvedGuardianUserId = guardianResolver.resolve(authorization, guardianUserId);
    return ResponseEntity.ok(
        ApiResponse.ok(childQueryService.getChild(resolvedGuardianUserId, childId)));
  }
}
