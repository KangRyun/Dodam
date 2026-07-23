package com.ssafy.b209.infrastructure.ai.observation;

/** 관찰 리포트 생성 AI 호출 실패를 HTTP 구현 세부사항과 분리해 전달한다. */
public class AiObservationClientException extends RuntimeException {

  /** 호출 실패를 상위 계층이 안정적으로 분류하기 위한 최소 오류 유형이다. */
  public enum Type {
    /** 요청 검증, AI 서버 4xx 또는 일반 연결 실패다. */
    REQUEST_FAILED,
    /** 연결 또는 응답 대기 제한 시간을 초과했다. */
    TIMEOUT,
    /** 응답 Body가 없거나 JSON·계약 Validation이 유효하지 않다. */
    INVALID_RESPONSE,
    /** AI 서버가 5xx 응답을 반환했다. */
    SERVER_ERROR
  }

  private final Type type;

  /**
   * 민감한 원문 없이 오류 유형만 포함하는 Client Exception을 생성한다.
   *
   * @param type 호출 실패 유형
   */
  public AiObservationClientException(Type type) {
    this(type, null);
  }

  /**
   * 원인을 보존하되 외부 응답 원문이나 URL을 메시지에 포함하지 않는 Client Exception을 생성한다.
   *
   * @param type 호출 실패 유형
   * @param cause 내부 원인 예외
   */
  public AiObservationClientException(Type type, Throwable cause) {
    super(type.name(), cause);
    this.type = type;
  }

  /**
   * 상위 계층이 세부 HTTP 예외에 의존하지 않고 처리할 오류 유형을 반환한다.
   *
   * @return 호출 실패 유형
   */
  public Type getType() {
    return type;
  }
}
