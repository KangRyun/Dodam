package com.ssafy.b209.infrastructure.ai;

import com.ssafy.b209.conversation.dto.AiQuestionRequest;
import com.ssafy.b209.conversation.dto.AiQuestionResponse;

/** 목표 FastAPI 질문 생성 계약을 호출하는 외부 시스템 경계다. */
public interface AiQuestionClient {

  AiQuestionResponse generate(AiQuestionRequest request, String requestId);
}
