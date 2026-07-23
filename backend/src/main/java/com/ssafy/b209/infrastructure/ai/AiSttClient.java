package com.ssafy.b209.infrastructure.ai;

/** 최신 내부 STT endpoint를 호출하는 Spring의 외부 시스템 경계다. */
public interface AiSttClient {

  /**
   * 검증된 음성 Stream을 내부 STT에 전달한다.
   *
   * @param request 비식별 일반 파일명과 음성 Stream
   * @return 아직 DB에 반영되지 않은 검증 대상 STT 응답
   * @throws AiSttClientException 내부 HTTP·timeout·schema 오류가 발생한 경우
   */
  AiSttResponse transcribe(AiSttRequest request);
}
