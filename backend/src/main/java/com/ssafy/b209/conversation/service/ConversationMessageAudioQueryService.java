package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.exception.ConversationMessageAudioErrorCode;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.AudioStorageErrorCode;
import com.ssafy.b209.storage.audio.OpenedAudio;
import com.ssafy.b209.storage.audio.StoredAudioContent;
import java.util.Locale;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 대화 음성 답변 원본을 프록시 스트리밍하기 위한 재생 자원을 조립하는 읽기 전용 서비스다.
 *
 * <p>메시지가 속한 대화 세션의 아동에 대한 연결 보호자 소유권을 먼저 검증한다. 읽기 경로이므로 음성 처리 동의 게이트는 적용하지 않고 소유권만 확인한다. 아동 음성 답변과
 * AI 질문 TTS 음성을 모두 서빙하며, 두 유형이 아니거나 원본 key가 없거나 저장소에서 원본을 열 수 없으면(삭제·유실 포함) 재생 자원 없음으로 판정한다. 내부 저장
 * key·절대 경로·발화 원문은 로그에 남기지 않는다.
 */
@Service
@Transactional(readOnly = true)
public class ConversationMessageAudioQueryService {

  private final ConversationHistoryMessageRepository messageRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final VoiceAnswerAuthorizationRepository authorizationRepository;
  private final AudioStorage audioStorage;
  private final AudioStorage ttsAudioStorage;

  /**
   * 음성 답변 재생 Use Case 의존성을 생성한다.
   *
   * @param messageRepository 대화 메시지 단건 조회 경계
   * @param conversationSessionRepository 대화 세션 조회 경계
   * @param drawingSessionRepository 대화와 아동을 연결하는 그림 세션 조회 경계
   * @param authorizationRepository 보호자-아동 소유권 조회 경계
   * @param audioStorage 아동 음성 원본 저장소
   * @param ttsAudioStorage 재생성 가능한 AI 질문 TTS 캐시 저장소
   */
  public ConversationMessageAudioQueryService(
      ConversationHistoryMessageRepository messageRepository,
      ConversationSessionRepository conversationSessionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      VoiceAnswerAuthorizationRepository authorizationRepository,
      @Qualifier("audioStorage") AudioStorage audioStorage,
      @Qualifier("ttsAudioStorage") AudioStorage ttsAudioStorage) {
    this.messageRepository = messageRepository;
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.authorizationRepository = authorizationRepository;
    this.audioStorage = audioStorage;
    this.ttsAudioStorage = ttsAudioStorage;
  }

  /**
   * 연결 보호자 소유권을 검증하고 음성 답변 원본을 여는 재생 자원을 조립한다.
   *
   * @param guardianUserId 인증에서 해석한 보호자 ID
   * @param messageId URL 대화 메시지 ID
   * @return 응답 Content-Type과 열린 음성 Stream을 담은 재생 자원
   * @throws BusinessException 메시지가 없거나(404), 조회 권한이 없거나(403), 재생할 원본이 없는(404) 경우
   */
  public VoiceAnswerAudioResource getPlayableAudio(Long guardianUserId, Long messageId) {
    ConversationHistoryMessage message =
        messageRepository
            .findById(messageId)
            .orElseThrow(
                () ->
                    new BusinessException(
                        ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND));
    authorize(guardianUserId, message.getConversationSessionId());

    String storageKey = message.getAudioStorageKey();
    if ((!message.isVoiceAnswer() && !message.isQuestion())
        || storageKey == null
        || storageKey.isBlank()) {
      throw new BusinessException(
          ConversationMessageAudioErrorCode.CONVERSATION_AUDIO_NOT_AVAILABLE);
    }
    return openOrNotAvailable(message, storageKey);
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
    Long childId = drawingSession.getChildId();
    if (!authorizationRepository.hasGuardianChildRelation(guardianUserId, childId)) {
      throw new BusinessException(ConversationMessageStatusErrorCode.CONVERSATION_ACCESS_DENIED);
    }
  }

  private VoiceAnswerAudioResource openOrNotAvailable(
      ConversationHistoryMessage message, String storageKey) {
    try {
      if (!message.isQuestion()) {
        return resource(audioStorage.read(storageKey), storageKey);
      }
      try {
        return resource(ttsAudioStorage.read(storageKey), storageKey);
      } catch (BusinessException cacheMiss) {
        if (cacheMiss.getErrorCode() != AudioStorageErrorCode.AUDIO_NOT_FOUND) {
          throw cacheMiss;
        }
        return resource(audioStorage.read(storageKey), storageKey);
      }
    } catch (BusinessException exception) {
      throw new BusinessException(
          ConversationMessageAudioErrorCode.CONVERSATION_AUDIO_NOT_AVAILABLE, exception);
    }
  }

  private VoiceAnswerAudioResource resource(StoredAudioContent content, String storageKey) {
    return new VoiceAnswerAudioResource(
        content.contentType(),
        new OpenedAudio(content.inputStream(), transferFilename(storageKey)));
  }

  private String transferFilename(String storageKey) {
    int dot = storageKey.lastIndexOf('.');
    String extension = dot < 0 ? "bin" : storageKey.substring(dot + 1).toLowerCase(Locale.ROOT);
    return "audio." + extension.replaceAll("[^a-z0-9]", "");
  }
}
