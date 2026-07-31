package com.ssafy.b209.drawing.controller;

import com.ssafy.b209.drawing.dto.response.EmotionCalendarResponse;
import com.ssafy.b209.drawing.service.EmotionCalendarQueryService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Positive;
import java.time.YearMonth;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 아동의 월간 감정 달력을 조회하는 HTTP API를 제공하는 Controller다.
 *
 * <p>연·월 범위 검증만 담당하며 권한 검증과 감정 집계는 {@link EmotionCalendarQueryService}에 위임한다.
 */
@Tag(name = "Emotion Calendar", description = "보호자 월간 감정 달력 조회 API")
@Validated
@RestController
@RequestMapping("/api/v1/children")
public class EmotionCalendarController {

  private static final int MIN_YEAR = 2000;
  private static final int MAX_YEAR = 2100;
  private static final int MIN_MONTH = 1;
  private static final int MAX_MONTH = 12;

  private final EmotionCalendarQueryService emotionCalendarQueryService;

  /**
   * 월간 감정 달력 조회 서비스를 사용하는 Controller를 생성한다.
   *
   * @param emotionCalendarQueryService 권한 검증과 감정 집계를 처리하는 읽기 서비스
   */
  public EmotionCalendarController(EmotionCalendarQueryService emotionCalendarQueryService) {
    this.emotionCalendarQueryService = emotionCalendarQueryService;
  }

  /**
   * 연결 보호자가 아동의 한 달 감정 달력을 조회한다.
   *
   * @param childId 조회 대상 아동 식별자
   * @param year 조회할 연도({@value #MIN_YEAR}~{@value #MAX_YEAR})
   * @param month 조회할 월({@value #MIN_MONTH}~{@value #MAX_MONTH})
   * @return HTTP 200과 공통 성공 응답으로 감싼 월간 감정 달력
   * @throws BusinessException 연도 또는 월이 허용 범위를 벗어난 경우
   */
  @Operation(
      summary = "보호자 월간 감정 달력 조회",
      description =
          "연결 보호자가 아동의 한 달 감정 달력을 조회합니다. "
              + "일자와 월 경계는 한국 시간대로 해석하며 활동이 없는 날은 응답에 포함하지 않습니다. "
              + "삭제·중단된 활동은 제외하며, 아동이 직접 선택한 감정만 포함합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "월간 감정 달력 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "아동 식별자 또는 연·월 값 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "인증이 필요함",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 아동을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{childId}/emotions/calendar")
  public ResponseEntity<ApiResponse<EmotionCalendarResponse>> getMonthlyEmotionCalendar(
      @Parameter(description = "조회 대상 아동 식별자", required = true) @PathVariable @Positive
          Long childId,
      @Parameter(description = "조회할 연도", required = true) @RequestParam int year,
      @Parameter(description = "조회할 월(1~12)", required = true) @RequestParam int month) {
    EmotionCalendarResponse response =
        emotionCalendarQueryService.getMonthlyCalendar(childId, toYearMonth(year, month));
    return ResponseEntity.ok(ApiResponse.ok(response));
  }

  private YearMonth toYearMonth(int year, int month) {
    if (year < MIN_YEAR || year > MAX_YEAR || month < MIN_MONTH || month > MAX_MONTH) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    return YearMonth.of(year, month);
  }
}
