package com.ssafy.b209.global.exception;

import com.ssafy.b209.global.response.ErrorCode;
import java.util.Objects;

/**
 * 서비스 또는 도메인 계층에서 예상 가능한 비즈니스 오류를 표현하는 예외다.
 *
 * <p>클라이언트에 전달할 안전한 {@link ErrorCode}를 보관하고 {@link GlobalExceptionHandler}에 전달한다. 내부 원인 메시지는 오류
 * 응답으로 노출하지 않는다.
 */
public class BusinessException extends RuntimeException {

  /** 전역 예외 처리기가 HTTP 응답으로 변환할 안전한 오류 코드다. */
  private final ErrorCode errorCode;

  /**
   * 지정한 오류 코드의 기본 메시지를 사용하는 예외를 생성한다.
   *
   * @param errorCode 전역 예외 처리기에 전달할 오류 코드
   * @throws NullPointerException {@code errorCode}가 {@code null}인 경우
   */
  public BusinessException(ErrorCode errorCode) {
    super(requireErrorCode(errorCode).getMessage());
    this.errorCode = errorCode;
  }

  /**
   * 지정한 오류 코드와 내부 원인을 보관하는 예외를 생성한다.
   *
   * @param errorCode 전역 예외 처리기에 전달할 오류 코드
   * @param cause 원인이 된 예외
   * @throws NullPointerException {@code errorCode}가 {@code null}인 경우
   */
  public BusinessException(ErrorCode errorCode, Throwable cause) {
    super(requireErrorCode(errorCode).getMessage(), cause);
    this.errorCode = errorCode;
  }

  /**
   * 이 예외에 대응하는 오류 코드를 반환한다.
   *
   * @return HTTP Status와 안전한 응답 정보를 제공하는 오류 코드
   */
  public ErrorCode getErrorCode() {
    return errorCode;
  }

  private static ErrorCode requireErrorCode(ErrorCode errorCode) {
    return Objects.requireNonNull(errorCode, "errorCode must not be null");
  }
}
