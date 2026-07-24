package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.TtsGenerateRequest;
import com.ssafy.b209.conversation.dto.TtsGenerateResponse;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.exception.QuestionTtsErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.tts.AiTtsClient;
import com.ssafy.b209.infrastructure.ai.tts.TtsSynthesis;
import com.ssafy.b209.infrastructure.ai.tts.TtsSynthesisCommand;
import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.StagedAudio;
import com.ssafy.b209.storage.audio.StoreAudioCommand;
import com.ssafy.b209.storage.audio.StoredAudio;
import java.io.ByteArrayInputStream;
import org.springframework.stereotype.Service;

/**
 * AI 질문(QUESTION) 텍스트를 음성으로 합성·저장하고 재생 메타를 반환하는 CONV-04 오케스트레이터다.
 *
 * <p>연결 보호자 소유권을 먼저 검증하고, 이미 성공 음성이 있으면 AI를 호출하지 않고 캐시 결과를 반환한다. 미스면 짧은 선점 트랜잭션으로 상태를 확보한 뒤 트랜잭션
 * 밖에서 AI 합성과 파일 저장을 수행하고 성공 결과만 반영한다. 실패는 저장 상태를 {@code FAILED}로 끝내고 안전한 오류만 노출한다. 내부 저장 key·절대
 * 경로·합성 원문은 로그나 응답에 남기지 않는다.
 */
@Service
public class QuestionTtsService {

  private static final String AUDIO_CONTENT_TYPE = "audio/mpeg";

  private final ConversationHistoryMessageRepository messageRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final VoiceAnswerAuthorizationRepository authorizationRepository;
  private final QuestionTtsPersistenceService persistenceService;
  private final AiTtsClient aiTtsClient;
  private final AudioStorage audioStorage;

  /**
   * 질문 음성 생성 Use Case 의존성을 생성한다.
   *
   * @param messageRepository 대화 메시지 단건 조회 경계
   * @param conversationSessionRepository 대화 세션 조회 경계
   * @param drawingSessionRepository 대화와 아동을 연결하는 그림 세션 조회 경계
   * @param authorizationRepository 보호자-아동 소유권 조회 경계
   * @param persistenceService 음성 상태 선점·완료 짧은 트랜잭션 경계
   * @param aiTtsClient Mock 기본 질문 TTS 합성 경계
   * @param audioStorage 합성 음성을 검증·승격 저장하는 경계
   */
  public QuestionTtsService(
      ConversationHistoryMessageRepository messageRepository,
      ConversationSessionRepository conversationSessionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      VoiceAnswerAuthorizationRepository authorizationRepository,
      QuestionTtsPersistenceService persistenceService,
      AiTtsClient aiTtsClient,
      AudioStorage audioStorage) {
    this.messageRepository = messageRepository;
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.authorizationRepository = authorizationRepository;
    this.persistenceService = persistenceService;
    this.aiTtsClient = aiTtsClient;
    this.audioStorage = audioStorage;
  }

  /**
   * 연결 보호자 소유권을 검증하고 질문 음성을 생성·조회한다.
   *
   * @param guardianUserId 인증에서 해석한 보호자 ID
   * @param messageId URL 질문 메시지 ID
   * @param request 검증된 음색·속도 요청
   * @return 재생 프록시 경로·자막·길이를 담은 응답
   * @throws BusinessException 메시지가 없거나(404), 권한이 없거나(403), 질문이 아니거나(400), 생성 중이거나(409), 합성이
   *     실패한(502) 경우
   */
  public TtsGenerateResponse generate(
      Long guardianUserId, Long messageId, TtsGenerateRequest request) {
    ConversationHistoryMessage message =
        messageRepository
            .findById(messageId)
            .orElseThrow(
                () ->
                    new BusinessException(
                        ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND));
    authorize(guardianUserId, message.getConversationSessionId());
    if (!message.isQuestion()) {
      throw new BusinessException(QuestionTtsErrorCode.TTS_NOT_APPLICABLE);
    }

    QuestionTtsClaimResult claim = persistenceService.claim(messageId);
    return switch (claim.action()) {
      case CACHE_HIT -> new TtsGenerateResponse(audioUrl(messageId), null, null, claim.subtitle());
      case IN_PROGRESS ->
          throw new BusinessException(QuestionTtsErrorCode.TTS_GENERATION_IN_PROGRESS);
      case CLAIMED -> synthesizeAndStore(messageId, claim.subtitle(), request);
    };
  }

  private TtsGenerateResponse synthesizeAndStore(
      Long messageId, String subtitle, TtsGenerateRequest request) {
    StoredAudio stored;
    try {
      TtsSynthesis synthesis =
          aiTtsClient.synthesize(
              new TtsSynthesisCommand(subtitle, request.voice(), request.speed()));
      stored = store(synthesis);
    } catch (RuntimeException exception) {
      persistenceService.markFailed(messageId);
      throw new BusinessException(QuestionTtsErrorCode.TTS_FAILED, exception);
    }

    String audioUrl = audioUrl(messageId);
    if (!persistenceService.completeSuccess(messageId, stored.storageKey(), audioUrl)) {
      audioStorage.delete(stored.storageKey());
      throw new BusinessException(QuestionTtsErrorCode.TTS_GENERATION_IN_PROGRESS);
    }
    return new TtsGenerateResponse(audioUrl, null, stored.durationMillis(), subtitle);
  }

  private StoredAudio store(TtsSynthesis synthesis) {
    StoreAudioCommand command =
        new StoreAudioCommand(
            new ByteArrayInputStream(synthesis.audio()),
            synthesis.audio().length,
            AUDIO_CONTENT_TYPE,
            "synthesis." + synthesis.audioFormat());
    StagedAudio staged = audioStorage.stage(command);
    try {
      return audioStorage.promote(staged);
    } catch (RuntimeException exception) {
      audioStorage.discard(staged);
      throw exception;
    }
  }

  private void authorize(Long guardianUserId, Long conversationSessionId) {
    ConversationSession session =
        conversationSessionRepository
            .findById(conversationSessionId)
            .orElseThrow(
                () ->
                    new BusinessException(
                        ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND));
    ConversationStartDrawingSession drawingSession =
        drawingSessionRepository
            .findById(session.getDrawingSessionId())
            .orElseThrow(
                () ->
                    new BusinessException(
                        ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND));
    if (!authorizationRepository.hasGuardianChildRelation(
        guardianUserId, drawingSession.getChildId())) {
      throw new BusinessException(ConversationMessageStatusErrorCode.CONVERSATION_ACCESS_DENIED);
    }
  }

  private String audioUrl(Long messageId) {
    return "/api/v1/conversation-messages/" + messageId + "/audio";
  }
}
