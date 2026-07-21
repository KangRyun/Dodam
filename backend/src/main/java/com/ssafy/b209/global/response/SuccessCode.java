package com.ssafy.b209.global.response;

import org.springframework.http.HttpStatus;

/**
 * API 성공 응답 코드가 제공해야 하는 HTTP Status, 애플리케이션 코드와 기본 메시지의 계약이다.
 *
 * <p>공통 성공 코드와 도메인별 성공 코드가 같은 규격으로 {@link ApiResponse}를 생성할 때 사용한다.
 */
public interface SuccessCode {

  /**
   * 성공 상황에 대응하는 HTTP Status를 반환한다.
   *
   * @return HTTP 응답에 사용할 상태
   */
  HttpStatus getHttpStatus();

  /**
   * 클라이언트가 성공 상황을 식별할 애플리케이션 코드를 반환한다.
   *
   * @return 애플리케이션 성공 코드
   */
  String getCode();

  /**
   * 성공 상황의 기본 설명을 반환한다.
   *
   * @return 성공 메시지
   */
  String getMessage();
}
