package com.ssafy.b209.infrastructure.ai.tts;

/** 질문 텍스트를 음성으로 합성하는 HTTP AI 서버 또는 개발용 Mock 구현을 사용하는 Application 경계다. */
public interface AiTtsClient {

  /**
   * 질문 텍스트 합성 요청을 활성화된 구현체에 전달하고 계약에 맞는 음성 결과를 반환한다.
   *
   * @param command 합성할 텍스트와 음색·속도 요청
   * @return 활성 구현체가 반환한 음성 Byte와 컨테이너 형식
   * @throws AiTtsClientException 요청·통신·응답 계약 처리에 실패한 경우
   */
  TtsSynthesis synthesize(TtsSynthesisCommand command);
}
