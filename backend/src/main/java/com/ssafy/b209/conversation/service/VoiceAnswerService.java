package com.ssafy.b209.conversation.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.domain.VoiceAnswerMessage;
import com.ssafy.b209.conversation.dto.VoiceAnswerMetadata;
import com.ssafy.b209.conversation.dto.VoiceAnswerResponse;
import com.ssafy.b209.conversation.exception.VoiceAnswerErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerMessageRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.StagedAudio;
import com.ssafy.b209.storage.audio.StoreAudioCommand;
import com.ssafy.b209.storage.audio.StoredAudio;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.HexFormat;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;

/**
 * CONV-05 음성 답변의 인증 이후 권한·동의·파일 검증·PENDING 메시지 생성을 처리한다.
 *
 * <p>이 서비스는 STT Client를 호출하거나 STT 결과를 갱신하지 않는다. 저장이 커밋된 뒤 {@link VoiceAnswerStoredEvent}를 발행해 289번
 * 처리기로 넘긴다.
 *
 * <p>응답 {@code messageType}은 {@link ConversationMessageTypeMapper}로 공개 Enum 값으로 변환한다. 조회·폴링 경로와 같은
 * 어휘를 쓰기 위한 것이며 DB CHECK 값은 바꾸지 않는다.
 */
@Service
public class VoiceAnswerService {
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final VoiceAnswerAuthorizationRepository authorizationRepository;
  private final VoiceAnswerMessageRepository messageRepository;
  private final AudioStorage audioStorage;
  private final ObjectMapper objectMapper;
  private final Clock clock;
  private final ApplicationEventPublisher eventPublisher;

  /**
   * 음성 답변 Use Case 의존성을 생성한다.
   *
   * @param conversationSessionRepository 세션 조회·비관 잠금 경계
   * @param drawingSessionRepository 대화와 아동을 연결하는 그림 세션 조회 경계
   * @param authorizationRepository 보호자 관계·필수/음성 동의 조회 경계
   * @param messageRepository QUESTION parent 검증·순번·답변 저장 경계
   * @param audioStorage 음성 전용 임시 검증·최종 저장 경계
   * @param objectMapper metadata fingerprint 직렬화 도구
   * @param clock 서버 생성 시각 기준
   * @param eventPublisher 커밋 후 STT 처리를 요청하는 이벤트 발행 경계
   */
  public VoiceAnswerService(
      ConversationSessionRepository conversationSessionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      VoiceAnswerAuthorizationRepository authorizationRepository,
      VoiceAnswerMessageRepository messageRepository,
      AudioStorage audioStorage,
      ObjectMapper objectMapper,
      Clock clock,
      ApplicationEventPublisher eventPublisher) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.authorizationRepository = authorizationRepository;
    this.messageRepository = messageRepository;
    this.audioStorage = audioStorage;
    this.objectMapper = objectMapper;
    this.clock = clock;
    this.eventPublisher = eventPublisher;
  }

  /**
   * 영구 파일을 만들기 전에 보호자·동의·세션·질문 parent를 검증하고 음성을 임시 저장한다.
   *
   * @param guardianUserId JWT Authentication에서 해석한 보호자 ID
   * @param conversationId URL 대화 세션 ID
   * @param metadata 파싱·검증된 multipart metadata
   * @param audio 업로드된 음성 part
   * @return checksum 및 실제 길이가 검증된 임시 음성
   * @throws BusinessException 권한·동의·세션·질문 또는 파일 검증에 실패한 경우
   */
  public StagedAudio stage(
      Long guardianUserId, Long conversationId, VoiceAnswerMetadata metadata, MultipartFile audio) {
    metadata.validate();
    validateCurrentRequest(guardianUserId, conversationId, metadata.questionMessageId());
    if (audio == null || audio.isEmpty()) {
      throw new BusinessException(
          com.ssafy.b209.storage.audio.AudioStorageErrorCode.EMPTY_AUDIO_FILE);
    }
    try {
      return audioStorage.stage(
          new StoreAudioCommand(
              audio.getInputStream(),
              audio.getSize(),
              audio.getContentType(),
              audio.getOriginalFilename()));
    } catch (IOException exception) {
      throw new BusinessException(VoiceAnswerErrorCode.INVALID_METADATA, exception);
    }
  }

  /**
   * 검증한 checksum과 metadata로 동일 multipart 요청을 식별하는 SHA-256 fingerprint를 만든다.
   *
   * @param metadata 사용자 제공 metadata
   * @param stagedAudio 실제 Byte checksum이 계산된 임시 음성
   * @return Redis 멱등성 key와 함께 사용하는 비밀값 없는 고정 길이 fingerprint
   */
  public String fingerprint(VoiceAnswerMetadata metadata, StagedAudio stagedAudio) {
    try {
      String material =
          stagedAudio.checksumSha256() + ':' + objectMapper.writeValueAsString(metadata);
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256")
                  .digest(material.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
    } catch (JsonProcessingException | NoSuchAlgorithmException exception) {
      throw new BusinessException(VoiceAnswerErrorCode.IDEMPOTENCY_UNAVAILABLE, exception);
    }
  }

  /**
   * 세션 비관 잠금 안에서 질문을 다시 검증하고 최종 파일·PENDING 답변 메시지를 함께 저장한다.
   *
   * <p>질문 수는 변경하지 않는다. DB 트랜잭션이 rollback되면 최종 파일을 보상 삭제하고, 발행한 STT 요청 이벤트도 커밋되지 않아 소비되지 않는다.
   *
   * @param guardianUserId JWT Authentication의 보호자 ID
   * @param conversationId URL 대화 세션 ID
   * @param metadata 부모 질문과 녹음 시각 metadata
   * @param stagedAudio Redis 선점 전 생성한 검증 완료 임시 음성
   * @return 외부 storage key·원본 파일명·절대 경로 없는 201 응답
   */
  @Transactional
  public ResponseEntity<?> persist(
      Long guardianUserId,
      Long conversationId,
      VoiceAnswerMetadata metadata,
      StagedAudio stagedAudio) {
    StoredAudio stored = null;
    try {
      ConversationSession session =
          conversationSessionRepository
              .findByIdForUpdate(conversationId)
              .orElseThrow(
                  () -> new BusinessException(VoiceAnswerErrorCode.CONVERSATION_NOT_FOUND));
      validateAccessAndState(guardianUserId, session);
      messageRepository
          .findQuestionByIdAndConversationSessionId(metadata.questionMessageId(), conversationId)
          .orElseThrow(
              () -> new BusinessException(VoiceAnswerErrorCode.QUESTION_MESSAGE_NOT_FOUND));
      int nextSequence =
          messageRepository.findMaxMessageSequenceByConversationSessionId(conversationId) + 1;
      stored = audioStorage.promote(stagedAudio);
      registerRollbackCompensation(stored.storageKey());
      VoiceAnswerMessage saved =
          messageRepository.saveAndFlush(
              VoiceAnswerMessage.pending(
                  conversationId,
                  metadata.questionMessageId(),
                  nextSequence,
                  stored.storageKey(),
                  stored.checksumSha256(),
                  LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)));
      VoiceAnswerResponse response =
          new VoiceAnswerResponse(
              saved.getId(),
              saved.getParentMessageId(),
              saved.getMessageSequence(),
              saved.getSenderType(),
              ConversationMessageTypeMapper.toPublicMessageType(saved.getMessageType()),
              saved.getRawText(),
              saved.getSttText(),
              saved.getSpeechStatus(),
              saved.getSttConfidence(),
              saved.isNeedsGuardianConfirmation(),
              saved.getCreatedAt());
      eventPublisher.publishEvent(new VoiceAnswerStoredEvent(saved.getId()));
      return ResponseEntity.status(HttpStatus.CREATED)
          .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
    } catch (DataIntegrityViolationException exception) {
      deleteAfterFailure(stored);
      throw new BusinessException(VoiceAnswerErrorCode.VOICE_ANSWER_STORAGE_CONFLICT, exception);
    } catch (RuntimeException exception) {
      deleteAfterFailure(stored);
      throw exception;
    }
  }

  /**
   * Redis 재생·거절 경로에서 아직 최종 승격되지 않은 임시 파일을 삭제한다.
   *
   * @param stagedAudio 이 요청에서 stage한 파일
   */
  public void discard(StagedAudio stagedAudio) {
    audioStorage.discard(stagedAudio);
  }

  private void validateCurrentRequest(
      Long guardianUserId, Long conversationId, Long questionMessageId) {
    ConversationSession session =
        conversationSessionRepository
            .findById(conversationId)
            .orElseThrow(() -> new BusinessException(VoiceAnswerErrorCode.CONVERSATION_NOT_FOUND));
    validateAccessAndState(guardianUserId, session);
    messageRepository
        .findQuestionByIdAndConversationSessionId(questionMessageId, conversationId)
        .orElseThrow(() -> new BusinessException(VoiceAnswerErrorCode.QUESTION_MESSAGE_NOT_FOUND));
  }

  private void validateAccessAndState(Long guardianUserId, ConversationSession session) {
    ConversationStartDrawingSession drawingSession =
        drawingSessionRepository
            .findById(session.getDrawingSessionId())
            .orElseThrow(() -> new BusinessException(VoiceAnswerErrorCode.CONVERSATION_NOT_FOUND));
    Long childId = drawingSession.getChildId();
    if (!authorizationRepository.hasGuardianChildRelation(guardianUserId, childId)) {
      throw new BusinessException(VoiceAnswerErrorCode.CONVERSATION_ACCESS_DENIED);
    }
    if (!authorizationRepository.hasRequiredConsents(childId)
        || !authorizationRepository.hasVoiceProcessingConsent(childId)) {
      throw new BusinessException(VoiceAnswerErrorCode.VOICE_CONSENT_REQUIRED);
    }
    if (!session.isConversing()) {
      throw new BusinessException(VoiceAnswerErrorCode.CONVERSATION_NOT_CONVERSING);
    }
  }

  private void registerRollbackCompensation(String storageKey) {
    if (!TransactionSynchronizationManager.isSynchronizationActive()) return;
    TransactionSynchronizationManager.registerSynchronization(
        new TransactionSynchronization() {
          @Override
          public void afterCompletion(int status) {
            if (status != STATUS_COMMITTED) {
              safelyDelete(storageKey);
            }
          }
        });
  }

  private void deleteAfterFailure(StoredAudio stored) {
    if (stored != null) safelyDelete(stored.storageKey());
  }

  private void safelyDelete(String storageKey) {
    try {
      audioStorage.delete(storageKey);
    } catch (RuntimeException ignored) {
      // DB rollback 원인을 파일 보상 삭제 실패가 덮어쓰지 않는다. 저장 key와 원본 정보는 로그에 남기지 않는다.
    }
  }
}
