package com.ssafy.b209.expert.controller;

import com.ssafy.b209.expert.dto.request.CreateExpertProfileRequest;
import com.ssafy.b209.expert.dto.request.UpdateExpertProfileRequest;
import com.ssafy.b209.expert.dto.response.ExpertProfilePageResponse;
import com.ssafy.b209.expert.dto.response.ExpertProfileResponse;
import com.ssafy.b209.expert.service.ExpertProfileCreationService;
import com.ssafy.b209.expert.service.ExpertProfileQueryService;
import com.ssafy.b209.expert.service.ExpertProfileUpdateService;
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
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 인증된 전문가가 본인의 공개 프로필을 관리하는 API 경계다.
 *
 * <p>요청 형식과 공통 응답만 조립하고 역할·단일 프로필·검증 상태 정책은 Application Service에 위임한다.
 */
@Tag(name = "Expert Profiles", description = "전문가 공개 프로필 API")
@Validated
@RestController
@RequestMapping("/api/v1/experts")
public class ExpertProfileController {

  private final ExpertProfileCreationService creationService;
  private final ExpertProfileQueryService queryService;
  private final ExpertProfileUpdateService updateService;

  /**
   * 전문가 프로필 생성 Use Case를 사용하는 Controller를 생성한다.
   *
   * @param creationService 프로필 권한 검증과 저장을 수행하는 서비스
   * @param queryService 공개 프로필 검색과 노출 정책을 적용하는 서비스
   * @param updateService 소유자 프로필의 부분 수정과 재검토 전이를 처리하는 서비스
   */
  public ExpertProfileController(
      ExpertProfileCreationService creationService,
      ExpertProfileQueryService queryService,
      ExpertProfileUpdateService updateService) {
    this.creationService = creationService;
    this.queryService = queryService;
    this.updateService = updateService;
  }

  /**
   * 공개 전문가 프로필을 조건과 페이지에 따라 조회한다.
   *
   * @param specialty 전문 분야 코드
   * @param consultationAvailable 상담 가능 여부
   * @param verifiedOnly 검증 완료 프로필만 조회할지 여부
   * @param keyword 표시명·소속 검색어
   * @param page 0부터 시작하는 페이지 번호
   * @param size 페이지 크기
   * @return HTTP 200과 전문가 프로필 페이지
   */
  @Operation(summary = "공개 전문가 목록 조회")
  @GetMapping
  public ResponseEntity<ApiResponse<ExpertProfilePageResponse>> getProfiles(
      @RequestParam(required = false) String specialty,
      @RequestParam(required = false) Boolean consultationAvailable,
      @RequestParam(defaultValue = "true") boolean verifiedOnly,
      @RequestParam(required = false) @Size(max = 50) String keyword,
      @RequestParam(defaultValue = "0") @Min(0) int page,
      @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {
    return ResponseEntity.ok(
        ApiResponse.of(
            CommonSuccessCode.OK,
            queryService.getProfiles(
                specialty, consultationAvailable, verifiedOnly, keyword, page, size)));
  }

  /**
   * 전문가 프로필의 공개 상세 정보를 조회한다.
   *
   * @param expertId 전문가 프로필 식별자
   * @return HTTP 200과 공개 프로필 상세
   * @throws BusinessException 프로필이 없거나 검증 전 타인 프로필인 경우
   */
  @Operation(summary = "공개 전문가 상세 조회")
  @GetMapping("/{expertId}")
  public ResponseEntity<ApiResponse<ExpertProfileResponse>> getProfile(
      @PathVariable @Min(1) Long expertId) {
    return ResponseEntity.ok(
        ApiResponse.of(CommonSuccessCode.OK, queryService.getProfile(expertId)));
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

  /**
   * 현재 인증된 전문가가 소유한 공개 프로필의 일부 필드를 수정한다.
   *
   * @param request 수정할 필드만 포함한 요청
   * @return HTTP 200과 변경 후 프로필
   * @throws BusinessException 활성 전문가 계정이 아니거나 등록된 프로필이 없는 경우
   */
  @Operation(
      summary = "내 전문가 프로필 수정",
      description = "전문 자격 관련 정보가 변경되면 검증 상태를 REVIEW_REQUIRED로 전환합니다.")
  @PatchMapping("/me/profile")
  public ResponseEntity<ApiResponse<ExpertProfileResponse>> update(
      @Valid @RequestBody UpdateExpertProfileRequest request) {
    return ResponseEntity.ok(ApiResponse.of(CommonSuccessCode.OK, updateService.update(request)));
  }
}
