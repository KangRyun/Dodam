package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.conversation.dto.TtsGenerateRequest;
import com.ssafy.b209.conversation.dto.TtsGenerateResponse;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.QuestionTtsService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 AI 질문 메시지의 TTS 음성을 생성·조회하는 CONV-04 공개 HTTP API다.
 *
 * <p>동기 POST로 처리하며, 이미 성공 음성이 있으면 AI를 재호출하지 않고 캐시 메타를 반환한다. 응답 {@code audioUrl}은 매 요청 인증·소유권을 검증하는
 * 프록시 스트리밍 상대 경로이며 내부 저장 위치를 노출하지 않는다. 운영에서는 JWT를 검증하는 {@link GuardianUserResolver}가 보호자를 식별하며,
 * 개발·테스트 프로필의 임시 Header 경계는 운영 인증을 대체하지 않는다.
 */
@Tag(name = "Conversations", description = "AI 대화 질문 음성 생성 API")
@RestController
@RequestMapping("/api/v1/conversation-messages")
public class QuestionTtsController {

  private final GuardianUserResolver guardianResolver;
  private final QuestionTtsService questionTtsService;

  /**
   * 질문 음성 생성 Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT 전환 전 개발용 보호자 식별 경계
   * @param questionTtsService 소유권 검증·캐시 조회·합성 저장 Use Case
   */
  public QuestionTtsController(
      GuardianUserResolver guardianResolver, QuestionTtsService questionTtsService) {
    this.guardianResolver = guardianResolver;
    this.questionTtsService = questionTtsService;
  }

  /**
   * AI 질문 메시지의 TTS 음성을 생성하거나 캐시된 결과를 조회한다.
   *
   * @param messageId 질문 대화 메시지 식별자
   * @param authorization 운영 JWT 검증기 또는 개발·테스트 임시 경계가 해석할 Authorization Header
   * @param guardianUserId 개발·테스트에서만 사용하는 임시 보호자 Header
   * @param request 검증된 음색·속도 요청 Body
   * @return 음성 재생 경로·자막·길이를 담은 성공 응답
   * @throws BusinessException 메시지가 없거나(404), 권한이 없거나(403), 질문이 아니거나(400), 생성 중이거나(409), 합성이
   *     실패한(502) 경우
   */
  @Operation(
      summary = "질문 음성 생성",
      description = "AI 질문 메시지 텍스트를 TTS 음성으로 생성하거나 캐시된 음성 메타를 반환합니다. 내부 저장 위치는 노출하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "질문 음성 생성 또는 캐시 조회 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "요청 값 오류 또는 질문 메시지가 아님",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "대화 접근 권한 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "대화 메시지 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "이미 음성 생성이 진행 중",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "502",
        description = "질문 음성 생성 실패",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping(
      value = "/{messageId}/tts",
      consumes = MediaType.APPLICATION_JSON_VALUE,
      produces = MediaType.APPLICATION_JSON_VALUE)
  public ResponseEntity<ApiResponse<TtsGenerateResponse>> generate(
      @PathVariable Long messageId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId,
      @Valid @RequestBody TtsGenerateRequest request) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    TtsGenerateResponse response = questionTtsService.generate(guardianId, messageId, request);
    return ResponseEntity.ok(ApiResponse.ok(response));
  }
}
