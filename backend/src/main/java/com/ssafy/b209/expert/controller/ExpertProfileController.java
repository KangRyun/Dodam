package com.ssafy.b209.expert.controller;

import com.ssafy.b209.expert.dto.request.CreateExpertProfileRequest;
import com.ssafy.b209.expert.dto.response.ExpertProfileResponse;
import com.ssafy.b209.expert.service.ExpertProfileCreationService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 인증된 전문가가 본인의 공개 프로필을 관리하는 API 경계다.
 *
 * <p>요청 형식과 공통 응답만 조립하고 역할·단일 프로필·검증 상태 정책은 Application Service에 위임한다.
 */
@Tag(name = "Expert Profiles", description = "전문가 공개 프로필 API")
@RestController
@RequestMapping("/api/v1/experts")
public class ExpertProfileController {

  private final ExpertProfileCreationService creationService;

  /**
   * 전문가 프로필 생성 Use Case를 사용하는 Controller를 생성한다.
   *
   * @param creationService 프로필 권한 검증과 저장을 수행하는 서비스
   */
  public ExpertProfileController(ExpertProfileCreationService creationService) {
    this.creationService = creationService;
  }

  /**
   * 현재 인증된 전문가의 공개 프로필을 최초 등록한다.
   *
   * @param request 공개 프로필 입력값
   * @return HTTP 201, 생성된 프로필 Location과 공통 응답
   * @throws BusinessException 사용자가 전문가가 아니거나 이미 프로필이 존재하는 경우
   */
  @Operation(summary = "내 전문가 프로필 등록", description = "EXPERT 역할 사용자의 프로필을 PENDING 상태로 생성합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "전문가 프로필 등록 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 검증 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "인증 필요",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "EXPERT 역할 또는 활성 계정 아님",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "전문가 프로필이 이미 존재함",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/me/profile")
  public ResponseEntity<ApiResponse<ExpertProfileResponse>> create(
      @Valid @RequestBody CreateExpertProfileRequest request) {
    ExpertProfileResponse response = creationService.create(request);
    return ResponseEntity.created(URI.create("/api/v1/experts/" + response.expertId()))
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
