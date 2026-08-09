package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.dto.EndConversationRequest;
import com.ssafy.b209.conversation.dto.EndConversationResponse;
import com.ssafy.b209.conversation.exception.ConversationEndErrorCode;
import com.ssafy.b209.conversation.service.ConversationEndService;
import com.ssafy.b209.conversation.service.ConversationQuestionIdempotencyStore;
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
 * 연결 보호자가 진행 중인 대화를 종료하고 그림 활동을 감정 회고 단계로 전환하는 공개 HTTP API다.
 *
 * <p>요청 형식과 멱등성 경계만 조율하며, 소유권 검증과 대화·그림 세션의 원자적 상태 전이는 {@link ConversationEndService}에 위임한다.
 */
@Tag(name = "Conversations", description = "AI 대화 세션 API")
@Validated
@RestController
@RequestMapping("/api/v1/conversations")
public class ConversationEndController {

  private static final int IDEMPOTENCY_KEY_MIN_LENGTH = 8;
  private static final int IDEMPOTENCY_KEY_MAX_LENGTH = 100;

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ConversationQuestionIdempotencyStore idempotencyStore;
  private final ConversationEndService conversationEndService;

  /**
   * 대화 종료 API의 인증, 멱등성과 상태 전이 의존성을 구성한다.
   *
   * @param currentUserResolver 현재 인증 사용자 식별자 Resolver
   * @param idempotencyStore Redis 최초 응답 저장·재생 경계
   * @param conversationEndService 대화 종료 상태 전이 서비스
   */
  public ConversationEndController(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ConversationQuestionIdempotencyStore idempotencyStore,
      ConversationEndService conversationEndService) {
    this.currentUserResolver = currentUserResolver;
    this.idempotencyStore = idempotencyStore;
    this.conversationEndService = conversationEndService;
  }

  /**
   * 진행 중 대화를 종료하고 저장된 종료 결과를 멱등하게 반환한다.
   *
   * @param conversationId 종료할 대화 세션 식별자
   * @param idempotencyKey 같은 요청 재전송을 식별하는 {@code Idempotency-Key} Header 값
   * @param request 종료 사유와 화면이 확인한 마지막 질문 식별자
   * @return HTTP 200과 종료 상태 및 다음 그림 활동 단계
   * @throws BusinessException Header 형식, 권한, 대화 상태 또는 최신 질문 검증에 실패한 경우
   */
  @Operation(summary = "대화 종료", description = "진행 중 대화를 종료하고 연결된 그림 활동을 REFLECTION 단계로 전환합니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "대화 종료 또는 동일 요청 재조회 성공"),
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
        description = "접근 가능한 대화 세션 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "대화 상태, 마지막 질문 또는 멱등 요청 충돌",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping("/{conversationId}/end")
  public ResponseEntity<?> end(
      @PathVariable @Positive Long conversationId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Valid @RequestBody EndConversationRequest request) {
    validateIdempotencyKey(idempotencyKey);
    Long guardianId = currentUserResolver.requireUserId();
    String uri = "/api/v1/conversations/" + conversationId + "/end";
    return idempotencyStore.execute(
        guardianId,
        uri,
        idempotencyKey,
        request,
        () -> success(conversationEndService.end(conversationId, request)),
        ConversationEndErrorCode.CONVERSATION_END_CONFLICT);
  }

  private ResponseEntity<ApiResponse<EndConversationResponse>> success(
      EndConversationResponse response) {
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
