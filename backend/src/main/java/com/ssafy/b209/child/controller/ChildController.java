package com.ssafy.b209.child.controller;

import com.ssafy.b209.child.dto.request.DeleteChildRequest;
import com.ssafy.b209.child.dto.request.RegisterChildRequest;
import com.ssafy.b209.child.dto.request.UpdateChildRequest;
import com.ssafy.b209.child.dto.request.UpdateChildTutorialProgressRequest;
import com.ssafy.b209.child.dto.response.ChildDetailResponse;
import com.ssafy.b209.child.dto.response.ChildRegistrationResponse;
import com.ssafy.b209.child.dto.response.ChildSummaryResponse;
import com.ssafy.b209.child.dto.response.ChildTutorialProgressResponse;
import com.ssafy.b209.child.service.ChildDeletionService;
import com.ssafy.b209.child.service.ChildQueryService;
import com.ssafy.b209.child.service.ChildRegistrationService;
import com.ssafy.b209.child.service.ChildTutorialService;
import com.ssafy.b209.child.service.ChildUpdateService;
import com.ssafy.b209.conversation.service.TemporaryGuardianResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import java.net.URI;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
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
  private final ChildRegistrationService childRegistrationService;
  private final ChildTutorialService childTutorialService;
  private final ChildUpdateService childUpdateService;
  private final ChildDeletionService childDeletionService;

  /**
   * 보호자 식별 경계와 아동 조회·등록 서비스를 사용하는 Controller를 생성한다.
   *
   * @param guardianResolver Access Token Principal에서 보호자 식별자를 해석하는 경계
   * @param childQueryService 아동 상세 조회 Use Case
   * @param childRegistrationService 아동 프로필 등록 Use Case
   * @param childTutorialService 아동 Tutorial 상태 변경 Use Case
   * @param childUpdateService 아동 프로필 부분 수정 Use Case
   * @param childDeletionService 아동 프로필 삭제 Use Case
   */
  public ChildController(
      TemporaryGuardianResolver guardianResolver,
      ChildQueryService childQueryService,
      ChildRegistrationService childRegistrationService,
      ChildTutorialService childTutorialService,
      ChildUpdateService childUpdateService,
      ChildDeletionService childDeletionService) {
    this.guardianResolver = guardianResolver;
    this.childQueryService = childQueryService;
    this.childRegistrationService = childRegistrationService;
    this.childTutorialService = childTutorialService;
    this.childUpdateService = childUpdateService;
    this.childDeletionService = childDeletionService;
  }

  /**
   * 요청 보호자 소유의 새 아동 프로필을 등록한다.
   *
   * <p>등록일 기준 만 나이 범위를 검증하고 보호자와의 관계와 응답 방식을 함께 저장한다. {@code profileImageFileId}는 계약 호환을 위해 받지만 현재
   * 사전 업로드 이미지를 연결하는 기반이 없어 프로필 이미지를 저장하지 않는다.
   *
   * @param request 등록할 아동 프로필 정보
   * @param authorization Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @param guardianUserId Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @return HTTP 201, 생성된 아동의 Location Header와 등록 결과 공통 응답
   */
  @Operation(
      summary = "아동 프로필 등록",
      description =
          "요청 보호자가 새 아동 프로필을 등록하고 보호자와의 관계와 응답 방식을 함께 저장합니다. "
              + "Authorization Bearer Access Token의 사용자 ID를 등록 보호자로 사용합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "아동 프로필 등록 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 오류 또는 허용 나이 범위를 벗어남",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "서버 내부 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<ChildRegistrationResponse>> registerChild(
      @Valid @RequestBody RegisterChildRequest request,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long resolvedGuardianUserId = guardianResolver.resolve(authorization, guardianUserId);
    ChildRegistrationResponse response =
        childRegistrationService.register(resolvedGuardianUserId, request);
    URI location = URI.create("/api/v1/children/" + response.childId());
    return ResponseEntity.created(location)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }

  /**
   * 요청 보호자에게 연결된 활성 아동 목록을 최근 활동 요약과 함께 조회한다.
   *
   * <p>조회만 수행하며 보호자 홈 카드에 필요한 요약 정보와 아동별 최근 활동 요약(마지막 활동 시각, 누적 그림 세션 수)을 반환한다. 연결된 아동이 없으면 빈 목록을
   * 반환하며 공통 응답의 {@code data}는 아동 배열이다.
   *
   * @param authorization Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @param guardianUserId Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @return HTTP 200과 최근 활동 요약을 포함한 아동 요약 목록 공통 응답
   */
  @Operation(
      summary = "아동 목록 조회",
      description =
          "요청 보호자에게 연결된 활성 아동 목록을 최근 활동 요약과 함께 조회합니다. "
              + "각 항목에 마지막 활동 시각과 누적 그림 세션 수를 담은 recentActivity를 포함하며 "
              + "공통 응답의 data는 아동 배열입니다. "
              + "조회만으로 아동이나 관계 상태를 변경하지 않습니다. "
              + "Authorization Bearer Access Token의 사용자 ID로 보호자 관계를 검증합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "아동 목록 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "500",
        description = "서버 내부 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<List<ChildSummaryResponse>>> getChildren(
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long resolvedGuardianUserId = guardianResolver.resolve(authorization, guardianUserId);
    return ResponseEntity.ok(ApiResponse.ok(childQueryService.getChildren(resolvedGuardianUserId)));
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

  /**
   * 연결된 보호자가 아동의 Tutorial 진행 상태를 조회한다.
   *
   * <p>조회는 상태를 변경하지 않으며, 마지막 단계와 완료 시각이 아직 없으면 응답의 해당 필드는 {@code null}이다.
   *
   * @param childId Tutorial 진행 상태를 조회할 아동 식별자
   * @param authorization Bearer Access Token
   * @param guardianUserId Test Profile 호환 검증에서만 사용하는 임시 Header
   * @return HTTP 200과 Tutorial 진행 상태 공통 응답
   */
  @Operation(
      summary = "아동 Tutorial 상태 조회",
      description =
          "연결된 보호자가 아동의 Tutorial 상태와 마지막 진행 단계를 조회합니다. "
              + "삭제되었거나 연결되지 않은 아동은 존재하지 않는 아동과 동일하게 응답합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "아동 Tutorial 상태 조회 성공"),
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
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{childId}/tutorial")
  public ResponseEntity<ApiResponse<ChildTutorialProgressResponse>> getTutorialProgress(
      @Parameter(description = "조회할 아동 식별자", required = true) @PathVariable @Positive Long childId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long resolvedGuardianUserId = guardianResolver.resolve(authorization, guardianUserId);
    return ResponseEntity.ok(
        ApiResponse.ok(childQueryService.getTutorialProgress(resolvedGuardianUserId, childId)));
  }

  /**
   * 연결된 보호자가 아동의 Tutorial 진행 상태와 마지막 단계를 변경한다.
   *
   * @param childId Tutorial 상태를 변경할 아동 식별자
   * @param request 변경할 Tutorial 상태와 마지막 단계
   * @param authorization Bearer Access Token
   * @param guardianUserId Test Profile 호환 검증에서만 사용하는 임시 Header
   * @return HTTP 200과 변경 후 Tutorial 진행 상태
   */
  @Operation(
      summary = "아동 Tutorial 상태 변경",
      description =
          "NOT_STARTED에서 IN_PROGRESS로 시작하고, 진행 중 마지막 단계를 저장하거나 "
              + "COMPLETED 또는 SKIPPED로 종료합니다. 종료 상태는 이전 상태로 되돌릴 수 없습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "아동 Tutorial 상태 변경 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 또는 아동 식별자 형식 오류",
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
        responseCode = "409",
        description = "허용되지 않는 Tutorial 상태 전이",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping("/{childId}/tutorial")
  public ResponseEntity<ApiResponse<ChildTutorialProgressResponse>> updateTutorialProgress(
      @Parameter(description = "변경할 아동 식별자", required = true) @PathVariable @Positive Long childId,
      @Valid @RequestBody UpdateChildTutorialProgressRequest request,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long resolvedGuardianUserId = guardianResolver.resolve(authorization, guardianUserId);
    return ResponseEntity.ok(
        ApiResponse.ok(
            childTutorialService.updateProgress(resolvedGuardianUserId, childId, request)));
  }

  /**
   * 요청 보호자에게 연결된 활성 아동 프로필에서 전달된 값만 변경한다.
   *
   * @param childId 변경할 아동 식별자
   * @param request 변경할 아동 프로필 값
   * @param authorization Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @param guardianUserId Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @return HTTP 200과 변경된 아동 상세 프로필 공통 응답
   */
  @Operation(
      summary = "아동 프로필 수정",
      description = "연결 보호자가 아동 프로필에서 전달한 값만 변경합니다. " + "응답 방식 목록을 전달하면 기존 목록을 요청 순서대로 교체합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "아동 프로필 수정 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 오류 또는 허용 나이 범위를 벗어남",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "아동이 없거나 삭제됐거나 요청 보호자에게 연결되지 않음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping("/{childId}")
  public ResponseEntity<ApiResponse<ChildDetailResponse>> updateChild(
      @Parameter(description = "변경할 아동 식별자", required = true) @PathVariable @Positive Long childId,
      @Valid @RequestBody UpdateChildRequest request,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long resolvedGuardianUserId = guardianResolver.resolve(authorization, guardianUserId);
    return ResponseEntity.ok(
        ApiResponse.ok(childUpdateService.update(resolvedGuardianUserId, childId, request)));
  }

  /**
   * 요청 보호자가 유일하게 연결된 아동 프로필을 삭제 상태로 전환한다.
   *
   * <p>삭제 범위는 서버 정책으로 고정하므로 Query {@code cascade}를 받지 않는다. 값이 오면 클라이언트가 삭제 범위를 지정할 수 있다고 오해하지 않도록
   * 무시하지 않고 거부한다.
   *
   * <p>확인 값 검증은 {@link ChildDeletionService}가 단독으로 수행한다. 본문 누락·공백·오값이 모두 같은 오류로 응답해야 하므로 Bean
   * Validation으로 나누지 않는다.
   *
   * @param childId 삭제할 아동 식별자
   * @param request 명시적 삭제 확인 값이며 본문이 없으면 {@code null}
   * @param cascade 지원하지 않는 Query이며 값이 오면 400으로 거부한다
   * @param authorization Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @param guardianUserId Test Profile의 호환성 검증에만 사용하는 임시 Header
   * @return 본문이 없는 HTTP 204 응답
   */
  @Operation(
      summary = "아동 프로필 삭제",
      description =
          "confirmation이 DELETE이고 요청자가 유일한 연결 보호자인 경우 프로필을 삭제 상태로 전환하고 연관 파일 삭제를 예약합니다. "
              + "삭제 범위는 서버 정책으로 고정하므로 Query cascade는 지원하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "204",
        description = "아동 프로필 삭제 접수 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "아동 식별자 오류, 삭제 확인 값 오류(CHILD_400_002), 지원하지 않는 cascade Query(COMMON_400_001)",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "아동이 없거나 삭제됐거나 요청 보호자에게 연결되지 않음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "다른 보호자가 연결되어 전체 삭제 불가",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @DeleteMapping("/{childId}")
  public ResponseEntity<Void> deleteChild(
      @Parameter(description = "삭제할 아동 식별자", required = true) @PathVariable @Positive Long childId,
      @RequestBody(required = false) DeleteChildRequest request,
      @Parameter(hidden = true) @RequestParam(value = "cascade", required = false) String cascade,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    if (cascade != null) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    Long resolvedGuardianUserId = guardianResolver.resolve(authorization, guardianUserId);
    childDeletionService.delete(resolvedGuardianUserId, childId, request);
    return ResponseEntity.noContent().build();
  }
}
