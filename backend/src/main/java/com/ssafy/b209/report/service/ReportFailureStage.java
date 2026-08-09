package com.ssafy.b209.report.service;

/**
 * 리포트 생성이 어느 단계에서 멈췄는지 나타낸다 (S15P11B209 P0-2).
 *
 * <p>실패 로그에 단계를 남기는 이유는 <strong>같은 실패 코드가 서로 다른 곳에서 나오기 때문</strong>이다. {@code TIMEOUT} 하나만 봐서는 AI를
 * 못 불렀는지, 부르고 저장하다 끊겼는지 알 수 없다. 앞의 것은 다시 하면 되고 뒤의 것은 사람이 봐야 한다.
 */
public enum ReportFailureStage {
  /** AI 관찰 생성 호출 자체가 실패했다. */
  AI_CALL,

  /** 응답은 받았으나 계약 검증을 통과하지 못했다. */
  RESPONSE_VALIDATION,

  /** 검증까지 마친 결과를 저장하다 실패했다. */
  PERSISTENCE
}
