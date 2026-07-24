package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.conversation.dto.ConversationMessageSttStatusResponse;
import com.ssafy.b209.conversation.service.ConversationMessageSttStatusQueryService;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 연결 보호자가 대화 메시지의 STT 처리 상태와 변환 결과를 단건 조회하는 공개 HTTP API다.
 *
 * <p>클라이언트는 음성 답변 업로드(CONV-05) 이후 이 API로 처리 상태를 폴링한다. 운영에서는 JWT를 검증하는 {@link GuardianUserResolver}가
 * 보호자를 식별하며, 개발·테스트 프로필의 임시 Header 경계는 운영 인증을 대체하지 않는다.
 */
@Tag(name = "Conversations", description = "AI 대화 내역 조회 API")
@RestController
@RequestMapping("/api/v1/conversation-messages")
public class ConversationMessageDetailController {

  private final GuardianUserResolver guardianResolver;
  private final ConversationMessageSttStatusQueryService sttStatusQueryService;

  /**
   * Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT 전환 전 개발용 보호자 식별 경계
   * @param sttStatusQueryService 소유권 검증과 STT 상태 조립 읽기 서비스
   */
  public ConversationMessageDetailController(
      GuardianUserResolver guardianResolver,
      ConversationMessageSttStatusQueryService sttStatusQueryService) {
    this.guardianResolver = guardianResolver;
    this.sttStatusQueryService = sttStatusQueryService;
  }

  /**
   * 대화 메시지의 STT 처리 상태와 변환 결과를 조회한다.
   *
   * @param messageId 대화 메시지 식별자
   * @param authorization 운영 JWT 검증기 또는 개발·테스트 임시 경계가 해석할 Authorization Header
   * @param guardianUserId 개발·테스트에서만 사용하는 임시 보호자 Header
   * @return HTTP 200과 공통 성공 응답으로 감싼 STT 상태·결과
   * @throws BusinessException 메시지가 없거나 인증·권한 검증에 실패한 경우
   */
  @Operation(summary = "STT 처리 상태·결과 조회", description = "대화 메시지의 음성 처리 상태와 STT 변환 결과를 조회합니다.")
  @GetMapping("/{messageId}")
  public ResponseEntity<ApiResponse<ConversationMessageSttStatusResponse>> getSttStatus(
      @PathVariable Long messageId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    ConversationMessageSttStatusResponse response =
        sttStatusQueryService.getSttStatus(guardianId, messageId);
    return ResponseEntity.ok(ApiResponse.ok(response));
  }
}
