package com.ssafy.b209.conversation.service;

import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.domain.SkippableQuestionMessage;
import com.ssafy.b209.conversation.dto.SkipQuestionRequest;
import com.ssafy.b209.conversation.dto.SkipQuestionResponse;
import com.ssafy.b209.conversation.exception.QuestionSkipErrorCode;
import com.ssafy.b209.conversation.repository.ConversationEndAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.SkippableQuestionMessageRepository;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보호자 권한과 대화 상태를 확인한 뒤 AI 질문을 건너뜀으로 표시한다(CONV-08).
 *
 * <p>대화 세션을 비관 잠금으로 잡고 질문을 갱신해, 같은 대화에 대한 동시 요청이 순번·상태를 엇갈리게 바꾸지 못하게 한다. 질문 수와 대화 상태는 바꾸지 않으며 건너뜀
 * 표시만 남긴다.
 */
@Service
public class QuestionSkipService {

  private final CurrentAuthenticatedUserResolver currentUserResolver;
  private final ConversationEndAuthorizationRepository authorizationRepository;
  private final ConversationSessionRepository conversationRepository;
  private final SkippableQuestionMessageRepository questionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final ConversationEventRecorder eventRecorder;

  /**
   * 질문 건너뛰기 서비스를 구성한다.
   *
   * @param currentUserResolver 현재 인증된 보호자 식별자 조회기
   * @param authorizationRepository 대화 접근 권한 조회 저장소
   * @param conversationRepository 대화 세션 잠금 조회 저장소
   * @param questionRepository 질문 건너뜀 표시 갱신 저장소
   * @param drawingSessionRepository 대화와 아동을 연결하는 그림 세션 조회 경계
   * @param eventRecorder 대화 행동 이벤트 적재기
   */
  public QuestionSkipService(
      CurrentAuthenticatedUserResolver currentUserResolver,
      ConversationEndAuthorizationRepository authorizationRepository,
      ConversationSessionRepository conversationRepository,
      SkippableQuestionMessageRepository questionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      ConversationEventRecorder eventRecorder) {
    this.currentUserResolver = currentUserResolver;
    this.authorizationRepository = authorizationRepository;
    this.conversationRepository = conversationRepository;
    this.questionRepository = questionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.eventRecorder = eventRecorder;
  }

  /**
   * 현재 보호자가 접근 가능한 진행 중 대화에서 지정한 질문을 건너뛴다.
   *
   * <p>이미 건너뛴 질문에 다시 요청하면 오류 없이 같은 결과를 반환한다. 아이가 같은 버튼을 두 번 누르는 것을 실패로 만들 이유가 없다.
   *
   * @param conversationId 대화 세션 식별자
   * @param request 건너뛸 질문과 사유
   * @return 건너뜀 결과와 대화의 누적 건너뛴 질문 수
   * @throws BusinessException 접근할 수 없거나, 대화가 진행 중이 아니거나, 대화에 해당 질문이 없거나, 그림 단계 복귀를 요청한 경우
   */
  @Transactional
  public SkipQuestionResponse skip(Long conversationId, SkipQuestionRequest request) {
    Long guardianUserId = currentUserResolver.requireUserId();
    if (!authorizationRepository.hasConversationAccess(guardianUserId, conversationId)) {
      throw new BusinessException(QuestionSkipErrorCode.CONVERSATION_NOT_FOUND);
    }
    // 역방향 단계 전이는 이어그리기 저장 경로와 얽혀 있어 이 API에서 제공하지 않는다.
    // 조용히 무시하면 화면이 그림 단계로 넘어간 줄 알고 진행하므로 명시적으로 거절한다.
    if (request.requestsReturnToDrawing()) {
      throw new BusinessException(
          QuestionSkipErrorCode.QUESTION_SKIP_RETURN_TO_DRAWING_UNSUPPORTED);
    }

    ConversationSession conversation =
        conversationRepository
            .findByIdForUpdate(conversationId)
            .orElseThrow(() -> new BusinessException(QuestionSkipErrorCode.CONVERSATION_NOT_FOUND));
    if (!conversation.isConversing()) {
      throw new BusinessException(QuestionSkipErrorCode.CONVERSATION_NOT_CONVERSING);
    }

    SkippableQuestionMessage question =
        questionRepository
            .findByIdAndConversationSessionId(request.questionMessageId(), conversationId)
            .filter(SkippableQuestionMessage::isQuestion)
            .orElseThrow(
                () -> new BusinessException(QuestionSkipErrorCode.QUESTION_MESSAGE_NOT_FOUND));

    boolean alreadySkipped = question.isSkipped();
    question.skip();
    questionRepository.flush();

    if (!alreadySkipped) {
      // 같은 버튼을 두 번 눌러 들어온 재요청은 기록하지 않는다. 건너뛰기는 이미 한 번 일어났고,
      //   여기서 또 남기면 소비자가 세는 "건너뛴 질문 수"가 탭 횟수만큼 부풀어 실제보다 산만한 아이로 보인다.
      recordSkipped(conversation, question.getId(), request);
    }

    return new SkipQuestionResponse(
        conversationId,
        question.getId(),
        true,
        alreadySkipped,
        questionRepository.countByConversationSessionIdAndSkippedTrue(conversationId),
        conversation.getConversationStatus());
  }

  /**
   * 건너뛰기를 대화 행동 이벤트로 남긴다 (S15P11B209-973).
   *
   * <p>아동을 찾지 못하면 기록을 건너뛴다. 여기까지 왔다는 것은 건너뛰기가 이미 성립했다는 뜻이라, 관측용 좌표를 못 구했다고 아이 화면에 오류를 띄울 이유가 없다.
   *
   * @param conversation 잠근 대화 세션
   * @param questionMessageId 건너뛴 질문 메시지 식별자
   * @param request 건너뛰기 요청
   */
  private void recordSkipped(
      ConversationSession conversation, Long questionMessageId, SkipQuestionRequest request) {
    Long childId =
        drawingSessionRepository
            .findById(conversation.getDrawingSessionId())
            .map(ConversationStartDrawingSession::getChildId)
            .orElse(null);
    if (childId == null) {
      return;
    }
    eventRecorder.recordSkip(
        new ConversationEventContext(
            conversation.getId(), childId, conversation.getDrawingSessionId()),
        questionMessageId,
        request.reason() == null ? null : request.reason().name());
  }
}
