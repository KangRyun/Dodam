package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.domain.SkipQuestionMessage;
import com.ssafy.b209.conversation.dto.QuestionSkipRequest;
import com.ssafy.b209.conversation.dto.QuestionSkipResponse;
import com.ssafy.b209.conversation.exception.QuestionSkipErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.SkipQuestionMessageRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 질문 건너뛰기의 권한·동의·상태·질문 검증과 {@code is_skipped} 표시, 선택적 그리기 단계 복귀를 담당한다.
 *
 * <p>형제 선택형 답변 API(149)의 소유권·동의·세션 잠금 기반을 재사용하되 새 메시지를 만들지 않고 기존 질문 메시지만 전이한다. 이미 건너뛴 질문을 다시 요청해도
 * 같은 결과를 반환하는 자연 멱등이며 질문 수는 되돌리지 않는다.
 */
@Service
public class QuestionSkipService {
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final VoiceAnswerAuthorizationRepository authorizationRepository;
  private final SkipQuestionMessageRepository messageRepository;

  /**
   * 질문 건너뛰기 Use Case 의존성을 생성한다.
   *
   * @param conversationSessionRepository 세션 조회·비관 잠금 경계
   * @param drawingSessionRepository 대화와 아동을 연결하고 그리기 단계를 전이하는 그림 세션 경계
   * @param authorizationRepository 보호자 관계·필수 동의 조회 경계
   * @param messageRepository 질문 검증·답변 존재 확인·건너뛰기 표시 경계
   */
  public QuestionSkipService(
      ConversationSessionRepository conversationSessionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      VoiceAnswerAuthorizationRepository authorizationRepository,
      SkipQuestionMessageRepository messageRepository) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.authorizationRepository = authorizationRepository;
    this.messageRepository = messageRepository;
  }

  /**
   * 세션 비관 잠금 안에서 권한·상태·질문을 검증하고 질문을 건너뛴 것으로 표시한다.
   *
   * @param guardianUserId 인증에서 해석한 보호자 ID
   * @param conversationId URL 대화 세션 ID
   * @param request 검증된 질문 건너뛰기 요청
   * @return 건너뛰기 결과와 처리 후 그림 세션 단계
   * @throws BusinessException 권한·동의·세션 상태·질문·답변 존재 검증에 실패한 경우
   */
  @Transactional
  public QuestionSkipResponse skip(
      Long guardianUserId, Long conversationId, QuestionSkipRequest request) {
    ConversationSession session =
        conversationSessionRepository
            .findByIdForUpdate(conversationId)
            .orElseThrow(() -> new BusinessException(QuestionSkipErrorCode.CONVERSATION_NOT_FOUND));
    ConversationStartDrawingSession drawingSession =
        validateAccessAndState(guardianUserId, session);

    Long questionMessageId = request.questionMessageId();
    if (!messageRepository.existsQuestion(questionMessageId, conversationId)) {
      throw new BusinessException(QuestionSkipErrorCode.QUESTION_MESSAGE_NOT_FOUND);
    }
    if (messageRepository.existsAnswerForQuestion(conversationId, questionMessageId)) {
      throw new BusinessException(QuestionSkipErrorCode.ANSWER_ALREADY_SUBMITTED);
    }

    SkipQuestionMessage question =
        messageRepository
            .findById(questionMessageId)
            .orElseThrow(
                () -> new BusinessException(QuestionSkipErrorCode.QUESTION_MESSAGE_NOT_FOUND));
    question.markSkipped();
    messageRepository.save(question);

    if (request.returnToDrawing()) {
      drawingSession.moveToDrawing();
    }

    return new QuestionSkipResponse(
        questionMessageId,
        true,
        session.getQuestionCount(),
        session.getMaxQuestionCount(),
        drawingSession.getCurrentStage().name());
  }

  private ConversationStartDrawingSession validateAccessAndState(
      Long guardianUserId, ConversationSession session) {
    ConversationStartDrawingSession drawingSession =
        drawingSessionRepository
            .findById(session.getDrawingSessionId())
            .orElseThrow(() -> new BusinessException(QuestionSkipErrorCode.CONVERSATION_NOT_FOUND));
    Long childId = drawingSession.getChildId();
    if (!authorizationRepository.hasGuardianChildRelation(guardianUserId, childId)) {
      throw new BusinessException(QuestionSkipErrorCode.CONVERSATION_ACCESS_DENIED);
    }
    if (!authorizationRepository.hasRequiredConsents(childId)) {
      throw new BusinessException(QuestionSkipErrorCode.CONSENT_REQUIRED);
    }
    if (session.isCompleted()) {
      throw new BusinessException(QuestionSkipErrorCode.CONVERSATION_ALREADY_COMPLETED);
    }
    if (!session.isConversing()) {
      throw new BusinessException(QuestionSkipErrorCode.CONVERSATION_NOT_CONVERSING);
    }
    return drawingSession;
  }
}
