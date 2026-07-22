package com.ssafy.b209.infrastructure.ai.drawing;

import com.ssafy.b209.analysis.dto.DrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisResponse;

/** 그림 분석 계약 DTO만으로 AI 서버와 통신하는 외부 시스템 경계다. */
public interface DrawingAnalysisClient {

  /**
   * 그림 Metadata 참조를 AI 서버에 전달하고 계약에 맞는 분석 응답을 반환한다.
   *
   * @param request 144번 이슈에서 확정한 그림 분석 요청
   * @return AI 서버가 반환한 유효한 그림 분석 응답
   * @throws DrawingAnalysisClientException 요청·통신·응답 계약 처리에 실패한 경우
   */
  DrawingAnalysisResponse analyze(DrawingAnalysisRequest request);
}
