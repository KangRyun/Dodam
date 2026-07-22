package com.ssafy.b209.infrastructure.ai;

/** AI 내부 HTTP 호출 실패의 재시도 정책을 구분한다. */
public class AiQuestionClientException extends RuntimeException {

  public enum Type {
    CONNECTION_FAILURE,
    READ_TIMEOUT,
    SAFETY_POLICY_BLOCKED,
    RESPONSE_SCHEMA_INVALID,
    OTHER
  }

  private final Type type;

  public AiQuestionClientException(Type type) {
    this(type, null);
  }

  public AiQuestionClientException(Type type, Throwable cause) {
    super(type.name(), cause);
    this.type = type;
  }

  public Type getType() {
    return type;
  }
}
