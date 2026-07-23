package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.conversation.dto.ConversationMessagePageResponse;
import com.ssafy.b209.conversation.service.ConversationMessageQueryService;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 대화 세션의 메시지 내역을 페이지로 조회하는 공개 HTTP API다.
 *
 * <p>운영에서는 JWT를 검증하는 {@link GuardianUserResolver}가 보호자를 식별하며, 개발·테스트 프로필의 임시 Header 경계는 운영 인증을 대체하지
 * 않는다.
 */
@Tag(name = "Conversations", description = "AI 대화 내역 조회 API")
@RestController
@RequestMapping("/api/v1/conversations")
public class ConversationMessageListController {
  private static final int MAX_PAGE_SIZE = 100;

  private final GuardianUserResolver guardianResolver;
  private final ConversationMessageQueryService messageQueryService;

  /**
   * Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT 전환 전 개발용 보호자 식별 경계
   * @param messageQueryService 소유권 검증·메시지 조립 읽기 서비스
   */
  public ConversationMessageListController(
      GuardianUserResolver guardianResolver, ConversationMessageQueryService messageQueryService) {
    this.guardianResolver = guardianResolver;
    this.messageQueryService = messageQueryService;
  }

  /**
   * 대화 세션의 메시지 내역을 순번 오름차순으로 페이지 조회한다.
   *
   * @param conversationId 대화 세션 식별자
   * @param page 0부터 시작하는 페이지 번호
   * @param size 페이지 크기
   * @param afterSequence 커서 기준 순번 또는 처음부터 조회할 {@code null}
   * @param authorization 운영 JWT 검증기 또는 개발·테스트 임시 경계가 해석할 Authorization Header
   * @param guardianUserId 개발·테스트에서만 사용하는 임시 보호자 Header
   * @return HTTP 200과 공통 성공 응답으로 감싼 메시지 페이지
   * @throws BusinessException 페이지 조건이 올바르지 않거나 인증·권한 검증에 실패한 경우
   */
  @Operation(summary = "대화 내역 조회", description = "대화 세션의 메시지 내역을 순번 오름차순으로 페이지 조회합니다.")
  @GetMapping("/{conversationId}/messages")
  public ResponseEntity<ApiResponse<ConversationMessagePageResponse>> getMessages(
      @PathVariable Long conversationId,
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "50") int size,
      @RequestParam(required = false) Integer afterSequence,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    validatePageRequest(page, size, afterSequence);
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    ConversationMessagePageResponse response =
        messageQueryService.getMessages(guardianId, conversationId, page, size, afterSequence);
    return ResponseEntity.ok(ApiResponse.ok(response));
  }

  private void validatePageRequest(int page, int size, Integer afterSequence) {
    if (page < 0
        || size < 1
        || size > MAX_PAGE_SIZE
        || (afterSequence != null && afterSequence < 0)) {
      throw new BusinessException(CommonErrorCode.INVALID_INPUT_VALUE);
    }
  }
}
