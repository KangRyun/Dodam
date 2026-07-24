package com.ssafy.b209.conversation.controller;

import com.ssafy.b209.conversation.service.ConversationMessageAudioQueryService;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.VoiceAnswerAudioResource;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.storage.audio.OpenedAudio;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * 연결 보호자가 대화 음성 답변의 원본 오디오를 재생하도록 백엔드 프록시 스트리밍으로 제공하는 공개 HTTP API다.
 *
 * <p>presigned URL을 발급하지 않고 매 요청 인증·소유권을 검증한 뒤 저장된 음성을 {@link StreamingResponseBody}로 중계한다. 응답은
 * {@code Cache-Control: private, no-store}로 캐시를 금지하며 내부 저장 위치·URL을 노출하지 않는다. 운영에서는 JWT를 검증하는 {@link
 * GuardianUserResolver}가 보호자를 식별하며, 개발·테스트 프로필의 임시 Header 경계는 운영 인증을 대체하지 않는다.
 */
@Tag(name = "Conversations", description = "AI 대화 내역 조회 API")
@RestController
@RequestMapping("/api/v1/conversation-messages")
public class ConversationMessageAudioController {

  private static final int STREAM_BUFFER_SIZE = 8192;

  private final GuardianUserResolver guardianResolver;
  private final ConversationMessageAudioQueryService audioQueryService;

  /**
   * Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT 전환 전 개발용 보호자 식별 경계
   * @param audioQueryService 소유권 검증과 재생 자원 조립 읽기 서비스
   */
  public ConversationMessageAudioController(
      GuardianUserResolver guardianResolver,
      ConversationMessageAudioQueryService audioQueryService) {
    this.guardianResolver = guardianResolver;
    this.audioQueryService = audioQueryService;
  }

  /**
   * 대화 음성 답변의 원본 오디오를 프록시 스트리밍으로 재생한다.
   *
   * @param messageId 대화 메시지 식별자
   * @param authorization 운영 JWT 검증기 또는 개발·테스트 임시 경계가 해석할 Authorization Header
   * @param guardianUserId 개발·테스트에서만 사용하는 임시 보호자 Header
   * @return 저장된 음성 Content-Type과 캐시 금지 Header를 담은 오디오 Stream 응답
   * @throws BusinessException 메시지가 없거나(404), 조회 권한이 없거나(403), 재생할 원본이 없는(404) 경우
   */
  @Operation(
      summary = "음성 답변 원본 재생",
      description = "연결 보호자가 대화 음성 답변의 원본 오디오를 백엔드 프록시 스트리밍으로 재생합니다. 내부 저장 위치는 노출하지 않습니다.")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "200",
        description = "음성 답변 원본 스트리밍 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "401",
        description = "Access Token 누락 또는 검증 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "403",
        description = "대화 접근 권한 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "대화 메시지 없음 또는 재생할 음성 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @GetMapping("/{messageId}/audio")
  public ResponseEntity<StreamingResponseBody> getVoiceAnswerAudio(
      @PathVariable Long messageId,
      @Parameter(hidden = true) @RequestHeader(value = "Authorization", required = false)
          String authorization,
      @Parameter(hidden = true) @RequestHeader(value = "X-Guardian-User-Id", required = false)
          String guardianUserId) {
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    VoiceAnswerAudioResource resource = audioQueryService.getPlayableAudio(guardianId, messageId);
    StreamingResponseBody body = stream(resource.audio());
    return ResponseEntity.ok()
        .cacheControl(CacheControl.noStore().cachePrivate())
        .contentType(MediaType.parseMediaType(resource.contentType()))
        .body(body);
  }

  private StreamingResponseBody stream(OpenedAudio audio) {
    return outputStream -> {
      try (OpenedAudio openedAudio = audio) {
        byte[] buffer = new byte[STREAM_BUFFER_SIZE];
        int read;
        while ((read = openedAudio.inputStream().read(buffer)) != -1) {
          outputStream.write(buffer, 0, read);
        }
      }
    };
  }
}
