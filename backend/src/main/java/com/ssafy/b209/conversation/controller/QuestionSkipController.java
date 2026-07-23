package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.conversation.dto.QuestionSkipRequest;
import com.ssafy.b209.conversation.dto.QuestionSkipResponse;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.QuestionSkipService;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import io.swagger.v3.oas.annotations.Operation;
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

/** 연결 보호자가 아동 대신 현재 AI 질문을 건너뛰는 CONV-08 공개 API다. */
@Tag(name = "Conversations", description = "AI 대화 질문 건너뛰기 API")
@RestController
@RequestMapping("/api/v1/conversations")
public class QuestionSkipController {
  private final GuardianUserResolver guardianResolver;
  private final QuestionSkipService questionSkipService;

  /**
   * 질문 건너뛰기 Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT Principal 우선 보호자 식별 경계
   * @param questionSkipService 권한·상태·질문 검증과 건너뛰기 표시 Use Case
   */
  public QuestionSkipController(
      GuardianUserResolver guardianResolver, QuestionSkipService questionSkipService) {
    this.guardianResolver = guardianResolver;
    this.questionSkipService = questionSkipService;
  }

  /**
   * 현재 AI 질문을 건너뛴 것으로 기록하고 처리 후 그림 세션 단계를 반환한다.
   *
   * <p>운영에서는 JWT Authentication만 허용하며 기존 임시 Header는 {@code test} 프로필에서만 Resolver가 제한적으로 해석한다.
   *
   * @param conversationId URL 대화 세션 ID
   * @param authorization Bearer Access JWT
   * @param guardianUserId test 프로필 전용 기존 임시 보호자 Header
   * @param request 검증된 질문 건너뛰기 요청 Body
   * @return 200 건너뛰기 결과
   */
  @Operation(summary = "질문 건너뛰기", description = "아동이 답변하지 않고 건너뛴 AI 질문을 건너뛴 것으로 기록합니다.")
  @PostMapping(value = "/{conversationId}/skip", consumes = MediaType.APPLICATION_JSON_VALUE)
  public ResponseEntity<ApiResponse<QuestionSkipResponse>> skip(
      @PathVariable Long conversationId,
      @RequestHeader(value = "Authorization", required = false) String authorization,
      @RequestHeader(value = "X-Guardian-User-Id", required = false) String guardianUserId,
      @Valid @RequestBody QuestionSkipRequest request) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    QuestionSkipResponse response = questionSkipService.skip(guardianId, conversationId, request);
    return ResponseEntity.ok(ApiResponse.of(CommonSuccessCode.OK, response));
  }
}
