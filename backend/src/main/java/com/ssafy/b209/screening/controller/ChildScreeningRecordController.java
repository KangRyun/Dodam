package com.ssafy.b209.screening.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import com.ssafy.b209.screening.dto.request.RegisterScreeningRecordRequest;
import com.ssafy.b209.screening.dto.response.ScreeningSummaryResponse;
import com.ssafy.b209.screening.service.ScreeningRecordCommandService;
import com.ssafy.b209.screening.service.ScreeningRecordQueryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 보호자가 다른 곳에서 받은 검사 결과를 기록·조회·삭제하는 HTTP API다.
 *
 * <p><strong>이 API 는 검사를 실시하지 않는다.</strong> 문항을 내보내지도, 응답을 받지도, 채점하지도 않는다 — 이미 나온 결과의 라벨과 출처만 옮겨
 * 적는다. 표준화 도구는 등록부에서 전부 승인 전 상태이며, 켜는 것은 코드 변경이 아니라 라이선스·임상 승인 절차다.
 */
@Tag(name = "Screening Records", description = "보호자가 입력한 검사 결과 기록 API")
@RestController
@RequestMapping("/api/v1/children/{childId}/screening-records")
public class ChildScreeningRecordController {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ScreeningRecordCommandService commandService;
  private final ScreeningRecordQueryService queryService;

  /**
   * 검사 기록 Controller를 구성한다.
   *
   * @param currentUserResolver Access Token 사용자 식별 경계
   * @param commandService 기록 등록·삭제 서비스
   * @param queryService 기록 조회 서비스
   */
  public ChildScreeningRecordController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ScreeningRecordCommandService commandService,
      ScreeningRecordQueryService queryService) {
    this.currentUserResolver = currentUserResolver;
    this.commandService = commandService;
    this.queryService = queryService;
  }

  /**
   * 보호자가 받은 검사 결과를 기록한다.
   *
   * @param childId 대상 아동 식별자
   * @param request 옮겨 적은 결과
   * @return 저장된 기록을 포함한 요약
   */
  @Operation(
      summary = "검사 결과 기록",
      description =
          "보호자가 다른 곳에서 받은 검사 결과를 옮겨 적는다. 앱은 검사를 실시하거나 채점하지 않으며, 등록부에 있는 도구만 기록할 수 있다. "
              + "임상 기록 보관 동의 이력이 확인돼야 한다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "기록 완료"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "등록되지 않은 검사 도구",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "접근 권한 없음 또는 동의 미확인",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<ScreeningSummaryResponse>> register(
      @PathVariable Long childId, @Valid @RequestBody RegisterScreeningRecordRequest request) {
    Long guardianUserId = currentUserResolver.requireUserId();
    commandService.register(guardianUserId, childId, request);
    return ResponseEntity.status(HttpStatus.CREATED)
        .body(
            ApiResponse.of(
                CommonSuccessCode.CREATED,
                queryService.summarizeForGuardian(guardianUserId, childId)));
  }

  /**
   * 아동의 검사 기록 요약을 조회한다.
   *
   * @param childId 대상 아동 식별자
   * @return 상태·문구·기록을 담은 요약
   */
  @Operation(
      summary = "검사 기록 조회",
      description = "보호자가 입력한 검사 기록과 함께, 이 앱이 표준화 선별검사를 제공하지 않는다는 상태를 돌려준다.")
  @GetMapping
  public ResponseEntity<ApiResponse<ScreeningSummaryResponse>> find(@PathVariable Long childId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    return ResponseEntity.ok(
        ApiResponse.of(
            CommonSuccessCode.OK, queryService.summarizeForGuardian(guardianUserId, childId)));
  }

  /**
   * 보호자가 기록을 지운다.
   *
   * @param childId 대상 아동 식별자
   * @param recordId 지울 기록 식별자
   * @return 남은 기록 요약
   */
  @Operation(summary = "검사 기록 삭제", description = "보호자가 자신이 입력한 검사 기록을 지운다. 조회에서 즉시 빠진다.")
  @DeleteMapping("/{recordId}")
  public ResponseEntity<ApiResponse<ScreeningSummaryResponse>> delete(
      @PathVariable Long childId, @PathVariable Long recordId) {
    Long guardianUserId = currentUserResolver.requireUserId();
    commandService.delete(guardianUserId, childId, recordId);
    return ResponseEntity.ok(
        ApiResponse.of(
            CommonSuccessCode.OK, queryService.summarizeForGuardian(guardianUserId, childId)));
  }
}
