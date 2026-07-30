package com.ssafy.b209.conversation.service;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.dto.EndConversationRequest;
import com.ssafy.b209.conversation.dto.EndConversationResponse;
import com.ssafy.b209.conversation.exception.ConversationEndErrorCode;
import com.ssafy.b209.conversation.repository.ConversationEndAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자 권한과 최신 질문 상태를 확인한 뒤 대화를 종료한다.
 *
 * <p>그림 작성 중 시작된 대화는 종료 후에도 Drawing 단계를 유지하며, 그림 완료 이후의 대화는 Reflection 단계로 전환한다.
 */
@Service
public class ConversationEndService {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ConversationEndAuthorizationRepository authorizationRepository;
  private final ConversationSessionRepository conversationRepository;
  private final DrawingSessionRepository drawingRepository;
  private final ConversationMessageRepository messageRepository;
  private final Clock clock;

  /**
   * 운영 환경의 UTC 시간을 사용하는 대화 종료 서비스를 구성한다.
   *
   * @param currentUserResolver 현재 인증된 보호자 식별자 조회기
   * @param authorizationRepository 대화 접근 권한 조회 저장소
   * @param conversationRepository 대화 세션 잠금 조회 저장소
   * @param drawingRepository 연결된 그림 세션 잠금 조회 저장소
   * @param messageRepository 최신 질문 조회 저장소
   */
  @Autowired
  public ConversationEndService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ConversationEndAuthorizationRepository authorizationRepository,
      ConversationSessionRepository conversationRepository,
      DrawingSessionRepository drawingRepository,
      ConversationMessageRepository messageRepository) {
    this(
        currentUserResolver,
        authorizationRepository,
        conversationRepository,
        drawingRepository,
        messageRepository,
        Clock.systemUTC());
  }

  ConversationEndService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ConversationEndAuthorizationRepository authorizationRepository,
      ConversationSessionRepository conversationRepository,
      DrawingSessionRepository drawingRepository,
      ConversationMessageRepository messageRepository,
      Clock clock) {
    this.currentUserResolver = currentUserResolver;
    this.authorizationRepository = authorizationRepository;
    this.conversationRepository = conversationRepository;
    this.drawingRepository = drawingRepository;
    this.messageRepository = messageRepository;
    this.clock = clock;
  }

  /**
   * 현재 보호자가 접근 가능한 진행 중 대화를 종료하고 연결된 그림 세션의 후속 단계를 확정한다.
   *
   * <p>이미 종료된 대화는 최초 완료 사유와 시각을 바꾸지 않고 같은 종료 결과를 반환한다. 마지막 질문 식별자가 전달되면 잠금 안에서 최신 질문과 비교해 오래된 화면
   * 상태로 인한 종료를 차단한다. 그림 작성 또는 최종 분석 중 종료하면 해당 단계를 유지하고, 최종 분석 완료 처리가 종료된 대화를 확인해 Reflection으로 전환한다.
   *
   * @param conversationId 종료할 대화 세션 식별자
   * @param request 종료 사유와 마지막 질문 식별자
   * @return 저장된 대화 종료 상태와 다음 그림 활동 단계
   * @throws BusinessException 접근할 수 없거나 대화·그림 세션이 없고, 최신 질문 또는 상태가 맞지 않는 경우
   */
  @Transactional
  public EndConversationResponse end(Long conversationId, EndConversationRequest request) {
    Long guardianUserId = currentUserResolver.requireUserId();
    if (!authorizationRepository.hasConversationAccess(guardianUserId, conversationId)) {
      throw new BusinessException(ConversationEndErrorCode.CONVERSATION_NOT_FOUND);
    }

    ConversationSession conversation =
        conversationRepository
            .findByIdForUpdate(conversationId)
            .orElseThrow(
                () -> new BusinessException(ConversationEndErrorCode.CONVERSATION_NOT_FOUND));

    DrawingSession drawingSession =
        drawingRepository
            .findNotDeletedByIdForUpdate(conversation.getDrawingSessionId())
            .orElseThrow(
                () -> new BusinessException(ConversationEndErrorCode.CONVERSATION_NOT_FOUND));

    if (conversation.isCompleted()) {
      return toResponse(conversation, drawingSession.getCurrentStage());
    }

    validateLastQuestion(conversation.getId(), request.lastQuestionMessageId());
    if (!conversation.isConversing()) {
      throw new BusinessException(ConversationEndErrorCode.CONVERSATION_NOT_CONVERSING);
    }

    conversation.complete(request.reason(), LocalDateTime.now(clock));
    DrawingStage nextStage = drawingSession.getCurrentStage();
    if (nextStage == DrawingStage.CONVERSING || nextStage == DrawingStage.REFLECTION) {
      drawingSession.enterReflection();
      nextStage = DrawingStage.REFLECTION;
    }
    return toResponse(conversation, nextStage);
  }

  private void validateLastQuestion(Long conversationId, Long lastQuestionMessageId) {
    if (lastQuestionMessageId == null) {
      return;
    }

    ConversationMessage latestQuestion =
        messageRepository
            .findFirstByConversationSessionIdAndMessageTypeOrderByMessageSequenceDesc(
                conversationId, "QUESTION")
            .orElseThrow(
                () ->
                    new BusinessException(
                        ConversationEndErrorCode.CONVERSATION_LAST_QUESTION_MISMATCH));
    if (!lastQuestionMessageId.equals(latestQuestion.getId())) {
      throw new BusinessException(ConversationEndErrorCode.CONVERSATION_LAST_QUESTION_MISMATCH);
    }
  }

  private EndConversationResponse toResponse(
      ConversationSession conversation, DrawingStage nextStage) {
    return new EndConversationResponse(
        conversation.getId(),
        conversation.getConversationStatus(),
        conversation.isCompleted(),
        conversation.getCompletionReason(),
        conversation.getCompletedAt(),
        nextStage);
  }
}
