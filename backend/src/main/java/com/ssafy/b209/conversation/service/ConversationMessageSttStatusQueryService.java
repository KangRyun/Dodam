package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.ConversationMessageSttStatusResponse;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 대화 메시지의 STT 처리 상태와 변환 결과 단건 조회를 담당하는 읽기 전용 서비스다.
 *
 * <p>메시지가 속한 대화 세션의 아동에 대한 연결 보호자 소유권을 검증한 뒤 메시지를 조립한다. 이미 저장된 STT 결과 조회는 소유권만으로 허용하며 음성 처리 동의 게이트를
 * 적용하지 않는다. 변환 결과는 처리 상태가 {@code SUCCESS}일 때만 노출하고, 내부 저장소 key·절대 경로·발화 원문 로그는 남기지 않는다.
 */
@Service
@Transactional(readOnly = true)
public class ConversationMessageSttStatusQueryService {
  private static final String SPEECH_STATUS_SUCCESS = "SUCCESS";

  private final ConversationHistoryMessageRepository messageRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final VoiceAnswerAuthorizationRepository authorizationRepository;

  /**
   * STT 상태 조회 Use Case 의존성을 생성한다.
   *
   * @param messageRepository 대화 메시지 단건 조회 경계
   * @param conversationSessionRepository 대화 세션 조회 경계
   * @param drawingSessionRepository 대화와 아동을 연결하는 그림 세션 조회 경계
   * @param authorizationRepository 보호자-아동 소유권 조회 경계
   */
  public ConversationMessageSttStatusQueryService(
      ConversationHistoryMessageRepository messageRepository,
      ConversationSessionRepository conversationSessionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      VoiceAnswerAuthorizationRepository authorizationRepository) {
    this.messageRepository = messageRepository;
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.authorizationRepository = authorizationRepository;
  }

  /**
   * 연결 보호자 소유권을 검증하고 메시지의 STT 상태·결과를 조회한다.
   *
   * @param guardianUserId 인증에서 해석한 보호자 ID
   * @param messageId URL 대화 메시지 ID
   * @return STT 처리 상태와 변환 결과 응답
   * @throws BusinessException 메시지가 없거나 보호자에게 조회 권한이 없는 경우
   */
  public ConversationMessageSttStatusResponse getSttStatus(Long guardianUserId, Long messageId) {
    ConversationHistoryMessage message =
        messageRepository
            .findById(messageId)
            .orElseThrow(
                () ->
                    new BusinessException(
                        ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND));
    authorize(guardianUserId, message.getConversationSessionId());
    return toResponse(message);
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

  private ConversationMessageSttStatusResponse toResponse(ConversationHistoryMessage message) {
    boolean success = SPEECH_STATUS_SUCCESS.equals(message.getSpeechStatus());
    return new ConversationMessageSttStatusResponse(
        message.getId(),
        message.getParentMessageId(),
        message.getMessageSequence(),
        message.getSenderType(),
        ConversationMessageTypeMapper.toPublicMessageType(message.getMessageType()),
        message.getRawText(),
        success ? message.getSttText() : null,
        message.getSpeechStatus(),
        success ? message.getSttConfidence() : null,
        message.isNeedsGuardianConfirmation(),
        message.getCreatedAt());
  }
}
