package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.conversation.dto.StartConversationRequest;
import com.ssafy.b209.conversation.dto.StartConversationResponse;
import com.ssafy.b209.conversation.exception.ActiveConversationExistsException;
import com.ssafy.b209.conversation.service.ConversationStartIdempotencyStore;
import com.ssafy.b209.conversation.service.ConversationStartService;
import com.ssafy.b209.conversation.service.TemporaryGuardianResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.net.URI;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 최종 명세의 그림 활동 하위 대화 세션 시작 HTTP API를 제공한다. */
@Tag(name = "Conversations", description = "AI 대화 세션 API")
@RestController
@RequestMapping("/api/v1/drawing-sessions")
public class ConversationStartController {
  private final TemporaryGuardianResolver guardianResolver;
  private final ConversationStartIdempotencyStore idempotencyStore;
  private final ConversationStartService conversationStartService;

  /**
   * 임시 인증 경계와 대화 시작 서비스를 사용하도록 Controller를 생성한다.
   *
   * @param guardianResolver 임시 보호자 식별 Header 처리 경계
   * @param idempotencyStore Redis 최초 응답 저장·재생 경계
   * @param conversationStartService 대화 세션 시작 업무 서비스
   */
  public ConversationStartController(
      TemporaryGuardianResolver guardianResolver,
      ConversationStartIdempotencyStore idempotencyStore,
      ConversationStartService conversationStartService) {
    this.guardianResolver = guardianResolver;
    this.idempotencyStore = idempotencyStore;
    this.conversationStartService = conversationStartService;
  }

  /**
   * 그림 활동에 연결되는 진행 중 대화 세션을 생성하고 Location Header를 반환한다.
   *
   * <p>정식 JWT 도입 전에는 임시 {@code X-Guardian-User-Id} Header로 보호자를 식별한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param authorization Bearer 형식을 확인하는 임시 Authorization Header
   * @param guardianUserId 임시 보호자 식별 Header
   * @param idempotencyKey 동일 요청 재전송을 식별하는 Header
   * @param request 분석 기준과 최대 질문 수 요청
   * @return 최초 또는 재생된 HTTP 상태, 생성 자원의 Location과 공통 응답
   */
  @Operation(summary = "AI 대화 세션 시작", description = "그림 활동에 연결된 대화 세션을 생성합니다.")
  @PostMapping("/{drawingSessionId}/conversations")
  public ResponseEntity<?> start(
      @Parameter(description = "그림 활동 세션 ID", required = true)
          @org.springframework.web.bind.annotation.PathVariable
          Long drawingSessionId,
      @RequestHeader(value = "Authorization", required = false) String authorization,
      @RequestHeader(value = "X-Guardian-User-Id", required = false) String guardianUserId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Valid @RequestBody(required = false) StartConversationRequest request) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    String uri = "/api/v1/drawing-sessions/" + drawingSessionId + "/conversations";
    return idempotencyStore.execute(
        guardianId,
        uri,
        idempotencyKey,
        request,
        () -> startResponse(guardianId, drawingSessionId, request));
  }

  private ResponseEntity<?> startResponse(
      Long guardianId, Long drawingSessionId, StartConversationRequest request) {
    try {
      StartConversationResponse response =
          conversationStartService.start(guardianId, drawingSessionId, request);
      return ResponseEntity.created(
              URI.create("/api/v1/conversations/" + response.conversationId()))
          .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
    } catch (ActiveConversationExistsException exception) {
      return ResponseEntity.status(exception.getErrorCode().getHttpStatus())
          .body(
              ApiErrorResponse.of(
                  exception.getErrorCode(),
                  Map.of("conversationId", exception.getConversationId())));
    } catch (BusinessException exception) {
      return ResponseEntity.status(exception.getErrorCode().getHttpStatus())
          .body(ApiErrorResponse.of(exception.getErrorCode()));
    }
  }
}
