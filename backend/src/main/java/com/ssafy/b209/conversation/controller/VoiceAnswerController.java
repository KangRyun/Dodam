package com.ssafy.b209.conversation.controller;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.dto.VoiceAnswerMetadata;
import com.ssafy.b209.conversation.exception.VoiceAnswerErrorCode;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.VoiceAnswerIdempotencyStore;
import com.ssafy.b209.conversation.service.VoiceAnswerService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.storage.audio.StagedAudio;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/** JWT 보호자가 아동의 음성 답변 파일을 저장하는 CONV-05 공개 API다. */
@Tag(name = "Conversations", description = "AI 대화 음성 답변 API")
@RestController
@RequestMapping("/api/v1/conversations")
public class VoiceAnswerController {
  private final GuardianUserResolver guardianResolver;
  private final VoiceAnswerService voiceAnswerService;
  private final VoiceAnswerIdempotencyStore idempotencyStore;
  private final ObjectMapper objectMapper;

  /**
   * 음성 답변 Controller 의존성을 생성한다.
   *
   * @param guardianResolver JWT Principal 우선 보호자 식별 경계
   * @param voiceAnswerService 파일·권한·메시지 저장 Use Case
   * @param idempotencyStore Redis 기반 최초 결과 재생 경계
   * @param objectMapper metadata JSON 파서
   */
  public VoiceAnswerController(
      GuardianUserResolver guardianResolver,
      VoiceAnswerService voiceAnswerService,
      VoiceAnswerIdempotencyStore idempotencyStore,
      ObjectMapper objectMapper) {
    this.guardianResolver = guardianResolver;
    this.voiceAnswerService = voiceAnswerService;
    this.idempotencyStore = idempotencyStore;
    this.objectMapper = objectMapper;
  }

  /**
   * 음성 파일을 검증·저장하고 STT 처리 대기(PENDING) 답변 메시지를 생성한다.
   *
   * <p>운영에서는 JWT Authentication만 허용한다. 기존 임시 Header는 {@code test} 프로필에서만 Resolver가 제한적으로 해석한다. STT
   * 호출·결과 갱신은 289번 범위라 이 endpoint는 수행하지 않는다.
   *
   * @param conversationId URL 대화 세션 ID
   * @param authorization Bearer Access JWT
   * @param guardianUserId test 프로필 전용 기존 임시 보호자 Header
   * @param idempotencyKey 동일 multipart 재전송 식별 Header
   * @param audio 필수 음성 binary part
   * @param metadataJson 필수 metadata JSON string part
   * @return 201 생성 결과 또는 Redis에 저장된 최초 결과
   */
  @Operation(summary = "음성 답변 업로드", description = "음성 파일을 저장하고 STT 대기 답변 메시지를 생성합니다.")
  @PostMapping(
      value = "/{conversationId}/answers/voice",
      consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<?> upload(
      @PathVariable Long conversationId,
      @RequestHeader(value = "Authorization", required = false) String authorization,
      @RequestHeader(value = "X-Guardian-User-Id", required = false) String guardianUserId,
      @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
      @RequestPart("audio") MultipartFile audio,
      @RequestPart("metadata") String metadataJson) {
    requireIdempotencyKey(idempotencyKey);
    Long guardianId = guardianResolver.resolve(authorization, guardianUserId);
    VoiceAnswerMetadata metadata = readMetadata(metadataJson);
    StagedAudio staged = voiceAnswerService.stage(guardianId, conversationId, metadata, audio);
    try {
      String uri = "/api/v1/conversations/" + conversationId + "/answers/voice";
      return idempotencyStore.execute(
          guardianId,
          uri,
          idempotencyKey,
          voiceAnswerService.fingerprint(metadata, staged),
          () -> persistAsResponse(guardianId, conversationId, metadata, staged));
    } finally {
      voiceAnswerService.discard(staged);
    }
  }

  private VoiceAnswerMetadata readMetadata(String metadataJson) {
    if (metadataJson == null || metadataJson.isBlank()) {
      throw new BusinessException(VoiceAnswerErrorCode.INVALID_METADATA);
    }
    try {
      VoiceAnswerMetadata metadata =
          objectMapper.readValue(metadataJson, VoiceAnswerMetadata.class);
      metadata.validate();
      return metadata;
    } catch (JsonProcessingException exception) {
      throw new BusinessException(VoiceAnswerErrorCode.INVALID_METADATA, exception);
    }
  }

  private ResponseEntity<?> persistAsResponse(
      Long guardianId, Long conversationId, VoiceAnswerMetadata metadata, StagedAudio stagedAudio) {
    try {
      return voiceAnswerService.persist(guardianId, conversationId, metadata, stagedAudio);
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
      throw new BusinessException(VoiceAnswerErrorCode.INVALID_METADATA);
    }
  }
}
