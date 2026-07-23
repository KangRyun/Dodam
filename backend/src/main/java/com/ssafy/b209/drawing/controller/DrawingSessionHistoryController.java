package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.dto.response.DrawingSessionHistoryPageResponse;
import com.ssafy.b209.drawing.service.DrawingSessionHistoryQueryService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.report.domain.ReportStatus;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Positive;
import java.time.LocalDate;
import java.util.Set;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 아동의 그림 활동 기록 목록을 페이지로 조회하는 HTTP API를 제공하는 Controller다.
 *
 * <p>요청 형식 검증과 페이지·정렬 구성만 담당하며, 권한 검증과 목록 조립은 {@link DrawingSessionHistoryQueryService}에 위임한다. 정렬은
 * 시작·완료 시각만 허용해 임의 컬럼 정렬을 차단한다.
 */
@Tag(name = "Activity History", description = "보호자 활동 기록 조회 API")
@Validated
@RestController
@RequestMapping("/api/v1/children")
public class DrawingSessionHistoryController {

  private static final int MAX_PAGE_SIZE = 100;
  private static final Set<String> SORTABLE_FIELDS = Set.of("startedAt", "completedAt");

  private final DrawingSessionHistoryQueryService historyQueryService;

  /**
   * 활동 기록 목록 조회 서비스를 사용하는 Controller를 생성한다.
   *
   * @param historyQueryService 권한 검증과 활동 기록 조립을 처리하는 읽기 서비스
   */
  public DrawingSessionHistoryController(DrawingSessionHistoryQueryService historyQueryService) {
    this.historyQueryService = historyQueryService;
  }

  /**
   * 연결 보호자가 아동의 그림 활동 기록 목록을 필터·정렬·페이지로 조회한다.
   *
   * @param childId 조회 대상 아동 식별자
   * @param from 활동 시작일 하한(ISO date), 미지정이면 {@code null}
   * @param to 활동 시작일 상한(ISO date), 미지정이면 {@code null}
   * @param drawingTypeCode 그림 활동 유형 코드 필터, 미지정이면 {@code null}
   * @param sessionStatus 세션 상태 필터, 미지정이면 {@code null}
   * @param reportStatus 최신 리포트 상태 필터, 미지정이면 {@code null}
   * @param page 0부터 시작하는 페이지 번호
   * @param size 페이지 크기
   * @param sort {@code 필드,방향} 형식의 정렬 조건이며 필드는 시작·완료 시각만 허용
   * @return HTTP 200과 공통 성공 응답으로 감싼 활동 기록 페이지
   * @throws BusinessException 페이지·정렬 조건이나 날짜 범위가 올바르지 않은 경우
   */
  @Operation(
      summary = "보호자 활동 기록 목록 조회",
      description =
          "연결 보호자가 아동의 그림 활동 기록을 필터와 정렬을 적용해 페이지로 조회합니다. "
              + "삭제된 활동은 제외하며, 아동이 직접 선택한 감정만 포함합니다. "
              + "정렬은 시작 시각과 완료 시각만 허용합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "활동 기록 목록 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "페이지·정렬·필터 값 또는 날짜 범위 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 아동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{childId}/drawing-sessions")
  public ResponseEntity<ApiResponse<DrawingSessionHistoryPageResponse>> getActivityHistory(
      @Parameter(description = "조회 대상 아동 식별자", required = true) @PathVariable @Positive
          Long childId,
      @Parameter(description = "활동 시작일 하한(ISO date)")
          @RequestParam(required = false)
          @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
          LocalDate from,
      @Parameter(description = "활동 시작일 상한(ISO date)")
          @RequestParam(required = false)
          @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
          LocalDate to,
      @Parameter(description = "그림 활동 유형 코드 필터") @RequestParam(required = false)
          String drawingTypeCode,
      @Parameter(description = "세션 상태 필터") @RequestParam(required = false)
          DrawingSessionStatus sessionStatus,
      @Parameter(description = "최신 리포트 상태 필터") @RequestParam(required = false)
          ReportStatus reportStatus,
      @Parameter(description = "0부터 시작하는 페이지 번호") @RequestParam(defaultValue = "0") int page,
      @Parameter(description = "페이지 크기(최대 100)") @RequestParam(defaultValue = "20") int size,
      @Parameter(description = "정렬 조건(startedAt 또는 completedAt, asc/desc)")
          @RequestParam(defaultValue = "startedAt,desc")
          String sort) {
    validateDateRange(from, to);
    Pageable pageable = toPageable(page, size, sort);
    DrawingSessionHistoryPageResponse response =
        historyQueryService.getHistory(
            childId, from, to, drawingTypeCode, sessionStatus, reportStatus, pageable);
    return ResponseEntity.ok(ApiResponse.ok(response));
  }

  private void validateDateRange(LocalDate from, LocalDate to) {
    if (from != null && to != null && from.isAfter(to)) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }

  private Pageable toPageable(int page, int size, String sort) {
    if (page < 0 || size < 1 || size > MAX_PAGE_SIZE) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    return PageRequest.of(page, size, toSort(sort));
  }

  private Sort toSort(String sort) {
    if (sort == null || sort.isBlank()) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    String[] parts = sort.split(",");
    String field = parts[0].trim();
    if (!SORTABLE_FIELDS.contains(field)) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    Sort.Direction direction = Sort.Direction.DESC;
    if (parts.length > 1) {
      direction =
          Sort.Direction.fromOptionalString(parts[1].trim())
              .orElseThrow(() -> new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE));
    }
    return Sort.by(direction, field);
  }
}
