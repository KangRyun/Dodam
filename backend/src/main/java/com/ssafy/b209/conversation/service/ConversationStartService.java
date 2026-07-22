package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.dto.StartConversationRequest;
import com.ssafy.b209.conversation.dto.StartConversationResponse;
import org.springframework.stereotype.Service;

/** 대화 시작의 DB 트랜잭션을 HTTP·Redis 멱등성 경계와 분리하는 공개 서비스다. */
@Service
public class ConversationStartService {
  private final ConversationStartPersistenceService persistenceService;

  /**
   * 대화 시작 서비스 의존성을 생성한다.
   *
   * @param persistenceService DB 트랜잭션 서비스
   */
  public ConversationStartService(ConversationStartPersistenceService persistenceService) {
    this.persistenceService = persistenceService;
  }

  /**
   * Redis 멱등성 키를 선점한 최초 요청의 대화 세션을 생성한다.
   *
   * @param guardianUserId 임시 인증 보호자 식별자
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param request 시작 요청
   * @return 새로 생성한 대화 세션 응답
   */
  public StartConversationResponse start(
      Long guardianUserId, Long drawingSessionId, StartConversationRequest request) {
    return persistenceService.create(guardianUserId, drawingSessionId, request);
  }
}
