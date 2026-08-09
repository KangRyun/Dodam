package com.ssafy.b209.consent.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.dto.request.CreateConsentRequest;
import com.ssafy.b209.consent.dto.response.ConsentChangeResponse;
import com.ssafy.b209.consent.dto.response.ConsentHistoryPageResponse;
import com.ssafy.b209.consent.dto.response.ConsentRegistrationResponse;
import com.ssafy.b209.consent.dto.response.ConsentStatusResponse;
import com.ssafy.b209.consent.dto.response.ConsentTermResponse;
import com.ssafy.b209.consent.service.ConsentHistoryQueryService;
import com.ssafy.b209.consent.service.ConsentRegistrationService;
import com.ssafy.b209.consent.service.ConsentStatusQueryService;
import com.ssafy.b209.consent.service.ConsentTermQueryService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 인증 사용자 또는 연결 아동의 약관 동의 등록·현황·버전별 이력 관리 HTTP API를 제공한다. */
@Tag(name = "Consents", description = "사용자·아동 동의 관리 API")
@RestController
@RequestMapping("/api/v1/consents")
public class ConsentController {

  private static final int MAX_IP_LENGTH = 45;
  private static final int MAX_USER_AGENT_LENGTH = 500;
  private static final int MAX_PAGE_SIZE = 100;

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ConsentRegistrationService registrationService;
  private final ConsentTermQueryService termQueryService;
  private final ConsentStatusQueryService statusQueryService;
  private final ConsentHistoryQueryService historyQueryService;

  /**
   * 동의 등록·약관·현황·이력 조회 Controller를 구성한다.
   *
   * @param currentUserResolver Access Token 사용자 식별 경계
   * @param registrationService 최초 동의 검증·저장 Service
   * @param termQueryService 현재 적용 약관 조회 Service
   * @param statusQueryService 사용자·아동 동의 현황 조회 Service
   * @param historyQueryService 접근 가능한 버전별 동의 이력 조회 Service
   */
  public ConsentController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ConsentRegistrationService registrationService,
      ConsentTermQueryService termQueryService,
      ConsentStatusQueryService statusQueryService,
      ConsentHistoryQueryService historyQueryService) {
    this.currentUserResolver = currentUserResolver;
    this.registrationService = registrationService;
    this.termQueryService = termQueryService;
    this.statusQueryService = statusQueryService;
    this.historyQueryService = historyQueryService;
  }

  /**
   * 인증 사용자가 접근할 수 있는 버전별 동의·철회 이력을 조회한다.
   *
   * @param childId 특정 아동 필터, 전체 접근 가능 이력이면 {@code null}
   * @param termCode 약관 코드 필터
   * @param from 기록일 하한
   * @param to 기록일 상한
   * @param page 0부터 시작하는 페이지 번호
   * @param size 페이지 크기
   * @return HTTP 200과 동의 이력 페이지
   */
  @Operation(summary = "동의 이력 조회", description = "사용자 본인과 현재 연결된 아동의 버전별 동의·철회 이력을 최신순으로 조회합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "동의 이력 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "페이지 또는 날짜 범위 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "아동 연결 보호자가 아님",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/history")
  public ResponseEntity<ApiResponse<ConsentHistoryPageResponse>> getConsentHistory(
      @RequestParam(required = false) Long childId,
      @RequestParam(required = false) String termCode,
      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "20") int size) {
    if ((childId != null && childId < 1)
        || (from != null && to != null && from.isAfter(to))
        || page < 0
        || size < 1
        || size > MAX_PAGE_SIZE
        || (long) page * size > Integer.MAX_VALUE) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
    return ResponseEntity.ok(
        ApiResponse.ok(
            historyQueryService.getHistory(
                currentUserResolver.requireUserId(), childId, termCode, from, to, page, size)));
  }

  /**
   * 사용자 본인과 선택 아동의 현재 동의 현황을 조회한다.
   *
   * <p>적용 범위의 필수 동의 충족 여부와 약관별 현재 동의 상태를 반환한다.
   *
   * @param childId 아동 대상 현황을 함께 조회할 아동 식별자, 사용자 약관만 조회하면 {@code null}
   * @return HTTP 200과 동의 현황 공통 응답
   */
  @Operation(
      summary = "동의 현황 조회",
      description = "로그인 사용자와 선택 아동의 현재 동의 현황을 조회합니다. childId를 지정하면 아동 대상 약관 현황을 함께 반환합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "동의 현황 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Query 값 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "아동 연결 보호자가 아님",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping
  public ResponseEntity<ApiResponse<ConsentStatusResponse>> getConsentStatus(
      @RequestParam(value = "childId", required = false) Long childId) {
    return ResponseEntity.ok(
        ApiResponse.ok(
            statusQueryService.getConsentStatus(currentUserResolver.requireUserId(), childId)));
  }

  /**
   * 현재 시행 중인 활성 약관 목록을 조회한다.
   *
   * <p>로그인 사용자에게 동일한 약관 목록을 제공하며 적용 범위와 버전으로 결과를 좁힐 수 있다.
   *
   * @param targetScope 적용 범위 필터, 전체 범위면 {@code null}
   * @param version 버전 필터, 전체 버전이면 {@code null}
   * @return HTTP 200과 현재 적용 약관 목록 공통 응답
   */
  @Operation(
      summary = "활성 약관 목록 조회",
      description = "로그인 사용자에게 현재 시행 중인 활성 약관 목록을 제공합니다. targetScope와 version으로 좁힐 수 있습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "활성 약관 목록 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Query 값 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/terms")
  public ResponseEntity<ApiResponse<List<ConsentTermResponse>>> getActiveTerms(
      @RequestParam(value = "targetScope", required = false) ConsentTargetScope targetScope,
      @RequestParam(value = "version", required = false) String version) {
    currentUserResolver.requireUserId();
    return ResponseEntity.ok(ApiResponse.ok(termQueryService.getActiveTerms(targetScope, version)));
  }

  /**
   * 활성 필수 약관을 확인하고 동의·철회 행위를 새 이력으로 저장한다.
   *
   * @param request 아동 ID와 약관별 행위
   * @param httpRequest 원격 IP와 User-Agent 증빙을 제공하는 HTTP 요청
   * @return HTTP 201과 저장된 이력 수
   */
  @Operation(summary = "최초 동의 등록", description = "현재 활성 약관에 대한 동의 행위를 append-only 이력으로 저장합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "동의 이력 등록 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "중복 약관 또는 대상 범위 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "필수 동의 누락 또는 보호자 관계 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "약관을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "비활성 또는 시행 전 약관",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping
  public ResponseEntity<ApiResponse<ConsentRegistrationResponse>> register(
      @Valid @RequestBody CreateConsentRequest request, HttpServletRequest httpRequest) {
    ConsentRegistrationResponse response =
        registrationService.register(
            currentUserResolver.requireUserId(),
            request,
            limit(httpRequest.getRemoteAddr(), MAX_IP_LENGTH),
            limit(httpRequest.getHeader(HttpHeaders.USER_AGENT), MAX_USER_AGENT_LENGTH));
    return ResponseEntity.status(HttpStatus.CREATED)
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }

  /**
   * 선택 약관의 동의·철회·재동의를 append-only 이력으로 기록한다.
   *
   * @param request 아동 ID와 변경할 선택 약관별 행위
   * @param httpRequest 원격 IP와 User-Agent 증빙을 제공하는 HTTP 요청
   * @return HTTP 200과 저장된 변경 이력 수
   */
  @Operation(summary = "선택 동의 변경", description = "선택 약관의 동의·철회·재동의를 기존 기록을 덮어쓰지 않고 새 이력으로 저장합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "선택 동의 변경 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "필수 약관 변경 또는 요청 범위 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "아동 연결 보호자가 아님",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "약관을 찾을 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "비활성 또는 시행 전 약관",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PatchMapping
  public ResponseEntity<ApiResponse<ConsentChangeResponse>> changeOptional(
      @Valid @RequestBody CreateConsentRequest request, HttpServletRequest httpRequest) {
    ConsentChangeResponse response =
        registrationService.changeOptional(
            currentUserResolver.requireUserId(),
            request,
            limit(httpRequest.getRemoteAddr(), MAX_IP_LENGTH),
            limit(httpRequest.getHeader(HttpHeaders.USER_AGENT), MAX_USER_AGENT_LENGTH));
    return ResponseEntity.ok(ApiResponse.ok(response));
  }

  private String limit(String value, int maximumLength) {
    if (value == null || value.isBlank()) {
      return null;
    }
    return value.length() <= maximumLength ? value : value.substring(0, maximumLength);
  }
}
