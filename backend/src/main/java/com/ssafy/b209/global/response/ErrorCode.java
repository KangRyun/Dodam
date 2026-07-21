package com.ssafy.b209.global.response;

import org.springframework.http.HttpStatus;

/**
 * API 오류 응답 코드가 제공해야 하는 HTTP Status, 애플리케이션 코드와 안전한 메시지의 계약이다.
 *
 * <p>공통 오류 코드와 도메인별 오류 코드가 같은 규격으로 {@link ApiErrorResponse}를 생성할 때 사용한다.
 */
public interface ErrorCode {

  /**
   * 오류 상황에 대응하는 HTTP Status를 반환한다.
   *
   * @return HTTP 응답에 사용할 상태
   */
  HttpStatus getHttpStatus();

  /**
   * 클라이언트가 오류 상황을 식별할 애플리케이션 코드를 반환한다.
   *
   * @return 애플리케이션 오류 코드
   */
  String getCode();

  /**
   * 클라이언트에 전달할 안전한 오류 메시지를 반환한다.
   *
   * @return 오류 메시지
   */
  String getMessage();
}
