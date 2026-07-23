package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.conversation.dto.OptionAnswerRequest;
import com.ssafy.b209.conversation.dto.OptionAnswerResponse;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.OptionAnswerService;
import com.ssafy.b209.conversation.service.VoiceAnswerIdempotencyStore;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 연결 보호자가 아동의 선택형 답변을 저장하는 CONV-06 공개 API다. */
@Tag(name = "Conversations", description = "AI 대화 선택형 답변 API")
@RestController
@RequestMapping("/api/v1/conversations")
public class OptionAnswerController {
  private final GuardianUserResolver guardianResolver;
  private final OptionAnswerService optionAnswerService;
  private final VoiceAnswerIdempotencyStore idempotencyStore;

  /**
   * 선택형 답변 Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT Principal 우선 보호자 식별 경계
   * @param optionAnswerService 권한·질문·선택지 검증과 저장 Use Case
   * @param idempotencyStore 음성 답변과 동일한 Redis 최초 결과 재생 경계
   */
  public OptionAnswerController(
      GuardianUserResolver guardianResolver,
      OptionAnswerService optionAnswerService,
      VoiceAnswerIdempotencyStore idempotencyStore) {
    this.guardianResolver = guardianResolver;
    this.optionAnswerService = optionAnswerService;
    this.idempotencyStore = idempotencyStore;
  }

  /**
   * 아동의 선택형 답변을 검증·저장하고 생성된 답변 메시지를 반환한다.
   *
   * <p>운영에서는 JWT Authentication만 허용하며 기존 임시 Header는 {@code test} 프로필에서만 Resolver가 제한적으로 해석한다.
   *
   * @param conversationId URL 대화 세션 ID
   * @param authorization Bearer Access JWT
   * @param guardianUserId test 프로필 전용 기존 임시 보호자 Header
   * @param idempotencyKey 동일 요청 재전송 식별 Header
   * @param request 검증된 선택형 답변 요청 Body
   * @return 201 생성 결과 또는 Redis에 저장된 최초 결과
   */
  @Operation(summary = "선택형 답변 저장", description = "아동이 선택한 선택지를 검증하고 답변 메시지로 저장합니다.")
  @PostMapping(
      value = "/{conversationId}/answers/option",
      consumes = MediaType.APPLICATION_JSON_VALUE)
  public ResponseEntity<?> submit(
      @PathVariable Long conversationId,
      @RequestHeader(value = "Authorization", required = false) String authorization,
      @RequestHeader(value = "X-Guardian-User-Id", required = false) String guardianUserId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @Valid @RequestBody OptionAnswerRequest request) {
    requireIdempotencyKey(idempotencyKey);
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    String uri = "/api/v1/conversations/" + conversationId + "/answers/option";
    return idempotencyStore.execute(
        guardianId,
        uri,
        idempotencyKey,
        optionAnswerService.fingerprint(request),
        () -> persistAsResponse(guardianId, conversationId, request));
  }

  private ResponseEntity<?> persistAsResponse(
      Long guardianId, Long conversationId, OptionAnswerRequest request) {
    try {
      OptionAnswerResponse response =
          optionAnswerService.submit(guardianId, conversationId, request);
      String location =
          "/api/v1/conversations/" + conversationId + "/messages/" + response.messageId();
      return ResponseEntity.status(HttpStatus.CREATED)
          .header(HttpHeaders.LOCATION, location)
          .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
    } catch (BusinessException exception) {
      return ResponseEntity.status(exception.getErrorCode().getHttpStatus())
          .body(ApiErrorResponse.of(exception.getErrorCode()));
    }
  }

  private void requireIdempotencyKey(String idempotencyKey) {
    if (idempotencyKey == null
        || idempotencyKey.isBlank()
        || idempotencyKey.length() < 8
        || idempotencyKey.length() > 100
        || idempotencyKey.chars().anyMatch(Character::isISOControl)) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }
}
