package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 아이가 말로 대화를 그만하겠다고 확인해 준 경우 대화를 {@code CHILD_REQUEST}로 종료한다.
 *
 * <p>아이가 "그만할래"라고 말하면 AI가 "여기까지 할까?"로 되묻는다. 여기서 칩을 누르면 FE가 종료 API를 호출하지만, 말로 "응"이라고만 답하면 호출할 주체가 없어
 * 같은 되묻기가 반복됐다. AI는 상태가 없어 대화를 끝낼 수 없으므로(S15P11B209-786) 확인 사실만 응답 필드로 전하고, 실제 종료는 이 서비스가 한다.
 *
 * <p>보호자 권한과 대화 소유는 {@link ConversationNextQuestionService}가 이미 검증한 뒤 호출한다. 종료 결과는 {@link
 * ConversationEndService}와 같아야 하므로 그림 활동 단계 전환도 같은 규칙으로 맞춘다 — 그러지 않으면 말로 끝낸 대화만 회고 단계로 넘어가지 못한다.
 */
@Service
class ChildRequestConversationEndService {

  private final ConversationSessionRepository conversationSessionRepository;
  private final DrawingSessionRepository drawingSessionRepository;
  private final Clock clock;

  ChildRequestConversationEndService(
      ConversationSessionRepository conversationSessionRepository,
      DrawingSessionRepository drawingSessionRepository,
      Clock clock) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.clock = clock;
  }

  /**
   * 진행 중인 대화를 아동 요청 사유로 종료하고 연결된 그림 활동의 다음 단계를 확정한다.
   *
   * <p>이미 종료된 대화는 최초 종료 사유와 시각을 바꾸지 않고 그대로 둔다. 같은 확인이 두 번 도착해도(멱등성 키가 다른 재시도 포함) 결과가 같아야 한다.
   *
   * @param conversationId 종료할 대화 세션 식별자
   * @throws BusinessException 대화나 그림 활동을 찾을 수 없거나 대화가 진행 중이 아닌 경우
   */
  @Transactional
  void endByChildRequest(Long conversationId) {
    ConversationSession session =
        conversationSessionRepository
            .findByIdForUpdate(conversationId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));
    if (session.isCompleted()) {
      return;
    }
    if (!session.isConversing()) {
      throw new BusinessException(ConversationStartErrorCode.INVALID_STATE_TRANSITION);
    }
    DrawingSession drawingSession =
        drawingSessionRepository
            .findNotDeletedByIdForUpdate(session.getDrawingSessionId())
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));

    session.complete(ConversationCompletionReason.CHILD_REQUEST, LocalDateTime.now(clock));
    // 그림을 그리는 중 시작된 대화는 그림 단계를 유지한다. 대화·회고 단계에서만 회고로 넘긴다.
    DrawingStage currentStage = drawingSession.getCurrentStage();
    if (currentStage == DrawingStage.CONVERSING || currentStage == DrawingStage.REFLECTION) {
      drawingSession.enterReflection();
    }
  }
}
