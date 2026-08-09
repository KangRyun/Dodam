package com.ssafy.b209.infrastructure.ai.drawing;

import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;

/** 그림 분석 계약 DTO만으로 HTTP AI 서버 또는 개발용 Mock 구현을 사용하는 Application 경계다. */
public interface DrawingAnalysisClient {

  /**
   * 정본 종합 분석 계약으로 그림 분석을 요청한다.
   *
   * @param command 저장된 분석과 이미지 Metadata를 포함한 호출 명령
   * @return AI 서버의 종합 분석 결과
   * @throws DrawingAnalysisClientException 요청·통신·응답 계약 처리에 실패한 경우
   */
  AiDrawingAnalysisResponse analyze(DrawingAnalysisClientCommand command);
}
