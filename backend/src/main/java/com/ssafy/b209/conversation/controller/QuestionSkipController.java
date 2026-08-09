package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.dto.SkipQuestionRequest;
import com.ssafy.b209.conversation.dto.SkipQuestionResponse;
import com.ssafy.b209.conversation.exception.QuestionSkipErrorCode;
import com.ssafy.b209.conversation.service.ConversationQuestionIdempotencyStore;
import com.ssafy.b209.conversation.service.QuestionSkipService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 현재 AI 질문을 건너뛰는 공개 HTTP API다(CONV-08).
 *
 * <p>요청 형식과 멱등성 경계만 조율하고, 권한·상태 검증과 건너뜀 표시는 {@link QuestionSkipService}에 위임한다. 멱등 처리 방식은 대화 종료 API와
 * 같다.
 */
@Tag(name = "Conversations", description = "AI 대화 세션 API")
@Validated
@RestController
@RequestMapping("/api/v1/conversations")
public class QuestionSkipController {

  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ConversationQuestionIdempotencyStore idempotencyStore;
  private final QuestionSkipService questionSkipService;

  /**
   * 질문 건너뛰기 API의 인증·멱등성·처리 의존성을 구성한다.
   *
   * @param currentUserResolver 현재 인증 사용자 식별자 Resolver
   * @param idempotencyStore Redis 최초 응답 저장·재생 경계
   * @param questionSkipService 질문 건너뜀 표시 서비스
   */
  public QuestionSkipController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ConversationQuestionIdempotencyStore idempotencyStore,
      QuestionSkipService questionSkipService) {
    this.currentUserResolver = currentUserResolver;
    this.idempotencyStore = idempotencyStore;
    this.questionSkipService = questionSkipService;
  }

  /**
   * 지정한 AI 질문을 건너뛰고 결과를 멱등하게 반환한다.
   *
   * @param conversationId 대화 세션 식별자
   * @param idempotencyKey 같은 요청 재전송을 식별하는 {@code Idempotency-Key} Header 값
   * @param request 건너뛸 질문 식별자와 사유
   * @return HTTP 200과 건너뜀 결과
   * @throws BusinessException Header 형식, 권한, 대화 상태 또는 질문 검증에 실패한 경우
   */
  @Operation(
      summary = "질문 건너뛰기",
      description = "진행 중 대화의 AI 질문을 건너뜀으로 표시합니다. 질문 수와 대화 상태는 바뀌지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "건너뛰기 또는 동일 요청 재조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Idempotency-Key 또는 요청 형식 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "접근 가능한 대화 세션 또는 질문 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "대화 상태, 미지원 옵션 또는 멱등 요청 충돌",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/{conversationId}/skip")
  public ResponseEntity<?> skip(
      @PathVariable @Positive Long conversationId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Valid @RequestBody SkipQuestionRequest request) {
    validateIdempotencyKey(idempotencyKey);
    Long guardianId = currentUserResolver.requireUserId();
    String uri = "/api/v1/conversations/" + conversationId + "/skip";
    return idempotencyStore.execute(
        guardianId,
        uri,
        idempotencyKey,
        request,
        () -> success(questionSkipService.skip(conversationId, request)),
        QuestionSkipErrorCode.QUESTION_SKIP_CONFLICT);
  }

  private ResponseEntity<ApiResponse<SkipQuestionResponse>> success(SkipQuestionResponse response) {
    return ResponseEntity.ok(ApiResponse.ok(response));
  }

  private void validateIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null
        || idempotencyKey.length() < IDEMPOTENCY_KEY_MIN_LENGTH
        || idempotencyKey.length() > IDEMPOTENCY_KEY_MAX_LENGTH
        || idempotencyKey.isBlank()
        || idempotencyKey.chars().anyMatch(Character::isISOControl)) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }
}
