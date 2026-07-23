package com.ssafy.b209.infrastructure.ai;

/** STT 내부 호출 결과를 재시도 가능성에 따라 구분하는 예외다. */
public class AiSttClientException extends RuntimeException {

  /** STT 재시도 및 실패 상태 전이 판단에 쓰는 오류 유형이다. */
  public enum Type {
    CONNECTION_FAILURE,
    AI_UPSTREAM_ERROR,
    READ_TIMEOUT,
    INVALID_INTERNAL_TOKEN,
    INVALID_REQUEST,
    RESPONSE_SCHEMA_INVALID,
    OTHER
  }

  private final Type type;

  public AiSttClientException(Type type) {
    this(type, null);
  }

  public AiSttClientException(Type type, Throwable cause) {
    super(type.name(), cause);
    this.type = type;
  }

  public Type getType() {
    return type;
  }
}
