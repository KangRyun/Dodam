package com.ssafy.b209.report.controller;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportListPageResponse;
import com.ssafy.b209.report.service.ReportListQueryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Positive;
import java.time.DateTimeException;
import java.time.LocalDate;
import org.springframework.data.domain.PageRequest;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 아동별 관찰 리포트 목록을 조회하는 공개 HTTP API를 제공한다.
 *
 * <p>요청 형식과 페이지 범위를 검증하고, 권한 확인과 목록 조립은 {@link ReportListQueryService}에 위임한다.
 */
@Tag(name = "Reports", description = "관찰 리포트 조회 API")
@Validated
@RestController
@RequestMapping("/api/v1/children")
public class ReportListController {

  private static final int MAX_PAGE_SIZE = 100;

  private final ReportListQueryService reportListQueryService;

  /**
   * 리포트 목록 Controller를 생성한다.
   *
   * @param reportListQueryService 권한 검증과 목록 조립을 담당하는 서비스
   */
  public ReportListController(ReportListQueryService reportListQueryService) {
    this.reportListQueryService = reportListQueryService;
  }

  /**
   * 아동의 관찰 리포트를 최신 생성 순으로 조회한다.
   *
   * @param childId 조회 대상 아동 식별자
   * @param from 활동일 하한이며 없으면 {@code null}
   * @param to 활동일 상한이며 없으면 {@code null}
   * @param drawingTypeCode 그림 유형 코드이며 없으면 {@code null}
   * @param reportStatus 리포트 상태이며 없으면 {@code null}
   * @param page 0부터 시작하는 페이지 번호
   * @param size 페이지 크기
   * @return 공통 성공 응답으로 감싼 리포트 페이지
   * @throws BusinessException 날짜 또는 페이지 범위가 올바르지 않은 경우
   */
  @Operation(summary = "아동별 관찰 리포트 목록 조회")
  @GetMapping("/{childId}/reports")
  public ResponseEntity<ApiResponse<ReportListPageResponse>> getReports(
      @PathVariable @Positive Long childId,
      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
      @RequestParam(required = false) String drawingTypeCode,
      @RequestParam(required = false) ReportStatus reportStatus,
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "20") int size) {
    validateDateRange(from, to);
    validatePage(page, size);
    ReportListPageResponse response =
        reportListQueryService.getReports(
            childId,
            from,
            to,
            normalize(drawingTypeCode),
            reportStatus,
            PageRequest.of(page, size));
    return ResponseEntity.ok(ApiResponse.ok(response));
  }

  private void validateDateRange(LocalDate from, LocalDate to) {
    if (from == null || to == null) {
      return;
    }
    if (from.isAfter(to)) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    try {
      if (to.isAfter(from.plusYears(1))) {
        throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
      }
    } catch (DateTimeException exception) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }

  private void validatePage(int page, int size) {
    if (page < 0 || size < 1 || size > MAX_PAGE_SIZE || (long) page * size > Integer.MAX_VALUE) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }

  private String normalize(String value) {
    return value == null || value.isBlank() ? null : value.trim();
  }
}
