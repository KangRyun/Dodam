package com.ssafy.b209.infrastructure.ai.observation;

import com.ssafy.b209.report.dto.ObservationGeneration;
import com.ssafy.b209.report.dto.ObservationGenerationRequest;

/** 관찰 리포트 생성 계약 DTO만으로 HTTP AI 서버 또는 개발용 Mock 구현을 사용하는 Application 경계다. */
public interface AiObservationClient {

  /**
   * 최종 분석 요청을 활성화된 관찰 생성 구현체에 전달하고 계약에 맞는 결과를 반환한다.
   *
   * @param request 최종 분석 관찰 생성 요청
   * @return 활성 구현체가 반환한 관찰 리포트 생성 결과와 원본 JSON
   * @throws AiObservationClientException 요청·통신·응답 계약 처리에 실패한 경우
   */
  ObservationGeneration generate(ObservationGenerationRequest request);
}
