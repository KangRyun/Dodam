package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.conversation.dto.NextQuestionRequest;
import com.ssafy.b209.conversation.dto.NextQuestionResponse;
import com.ssafy.b209.conversation.service.ConversationNextQuestionService;
import com.ssafy.b209.conversation.service.ConversationQuestionIdempotencyStore;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 대화 세션의 다음 AI 질문을 생성하도록 하는 공개 HTTP API다.
 *
 * <p>운영에서는 JWT를 검증하는 {@link GuardianUserResolver}가 필요하며, 개발·테스트 프로필의 임시 Header 경계는 운영 인증을 대체하지 않는다.
 */
@Tag(name = "Conversations", description = "AI 대화 질문 API")
@RestController
@RequestMapping("/api/v1/conversations")
public class ConversationNextQuestionController {
  private final GuardianUserResolver guardianResolver;
  private final ConversationQuestionIdempotencyStore idempotencyStore;
  private final ConversationNextQuestionService nextQuestionService;

  /**
   * Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT 전환 전 개발용 보호자 식별 경계
   * @param idempotencyStore Redis 최초 응답 재생 경계
   * @param nextQuestionService 권한·AI·저장 업무 서비스
   */
  public ConversationNextQuestionController(
      GuardianUserResolver guardianResolver,
      ConversationQuestionIdempotencyStore idempotencyStore,
      ConversationNextQuestionService nextQuestionService) {
    this.guardianResolver = guardianResolver;
    this.idempotencyStore = idempotencyStore;
    this.nextQuestionService = nextQuestionService;
  }

  /**
   * 다음 AI 질문을 생성하고 저장된 질문 메시지를 반환한다.
   *
   * @param conversationId 대화 세션 식별자
   * @param authorization 운영 JWT 검증기 또는 개발·테스트 임시 경계가 해석할 Authorization Header
   * @param guardianUserId 개발·테스트에서만 사용하는 임시 보호자 Header
   * @param idempotencyKey 동일 요청 재전송 식별 Header
   * @param request 외부 다음 질문 요청
   * @return 최초 또는 Redis에서 재생한 공통 성공·오류 응답
   * @throws BusinessException {@code Idempotency-Key}가 누락·공백이거나 인증이 실패한 경우
   */
  @Operation(summary = "다음 AI 질문 생성", description = "대화 세션에 다음 AI 질문을 생성하고 저장합니다.")
  @PostMapping("/{conversationId}/next-question")
  public ResponseEntity<?> nextQuestion(
      @PathVariable Long conversationId,
      @RequestHeader(value = "Authorization", required = false) String authorization,
      @RequestHeader(value = "X-Guardian-User-Id", required = false) String guardianUserId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Valid @RequestBody NextQuestionRequest request) {
    requireIdempotencyKey(idempotencyKey);
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    String uri = "/api/v1/conversations/" + conversationId + "/next-question";
    return idempotencyStore.execute(
        guardianId,
        uri,
        idempotencyKey,
        request,
        () -> createResponse(guardianId, conversationId, request));
  }

  private void requireIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null || idempotencyKey.isBlank()) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }

  private ResponseEntity<?> createResponse(
      Long guardianId, Long conversationId, NextQuestionRequest request) {
    try {
      NextQuestionResponse response =
          nextQuestionService.generate(guardianId, conversationId, request);
      return ResponseEntity.ok(ApiResponse.of(CommonSuccessCode.OK, response));
    } catch (BusinessException exception) {
      return ResponseEntity.status(exception.getErrorCode().getHttpStatus())
          .body(ApiErrorResponse.of(exception.getErrorCode()));
    }
  }
}
