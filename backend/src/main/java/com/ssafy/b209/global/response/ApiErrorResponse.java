package com.ssafy.b209.global.response;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import java.util.Objects;

/**
 * API 오류 결과를 안전하고 일관된 구조로 감싸는 불변 응답 객체다.
 *
 * <p>오류 상세 데이터는 Generic으로 지원하며 {@code success}는 항상 {@code false}다. HTTP Status는 응답 Body가 아닌
 * Controller 계층의 {@code ResponseEntity}로 전달한다.
 *
 * @param <T> 오류 상세 데이터 타입
 */
@JsonPropertyOrder({"success", "code", "message", "data"})
public final class ApiErrorResponse<T> {

  private final boolean success;
  private final String code;
  private final String message;
  private final T data;

  private ApiErrorResponse(String code, String message, T data) {
    this.success = false;
    this.code = code;
    this.message = message;
    this.data = data;
  }

  /**
   * 상세 데이터가 없는 오류 응답을 생성한다.
   *
   * @param errorCode HTTP Status, 코드와 안전한 메시지를 제공하는 오류 코드
   * @return {@code data}가 {@code null}인 오류 응답
   * @throws NullPointerException {@code errorCode}가 {@code null}인 경우
   */
  public static ApiErrorResponse<Void> of(ErrorCode errorCode) {
    return of(errorCode, null);
  }

  /**
   * 지정한 오류 코드와 상세 데이터로 응답을 생성한다.
   *
   * @param errorCode HTTP Status, 코드와 안전한 메시지를 제공하는 오류 코드
   * @param data 클라이언트에 전달할 안전한 오류 상세 데이터
   * @param <T> 오류 상세 데이터 타입
   * @return 지정한 오류 코드와 상세 데이터를 가진 오류 응답
   * @throws NullPointerException {@code errorCode}가 {@code null}인 경우
   */
  public static <T> ApiErrorResponse<T> of(ErrorCode errorCode, T data) {
    Objects.requireNonNull(errorCode, "errorCode must not be null");
    return new ApiErrorResponse<>(errorCode.getCode(), errorCode.getMessage(), data);
  }

  /**
   * 요청 성공 여부를 반환한다.
   *
   * @return 항상 {@code false}
   */
  @JsonProperty("success")
  public boolean success() {
    return success;
  }

  /**
   * 클라이언트가 오류 상황을 식별할 애플리케이션 코드를 반환한다.
   *
   * @return 오류 코드
   */
  @JsonProperty("code")
  public String code() {
    return code;
  }

  /**
   * 클라이언트에 전달할 안전한 오류 설명을 반환한다.
   *
   * @return 오류 메시지
   */
  @JsonProperty("message")
  public String message() {
    return message;
  }

  /**
   * 안전하게 가공된 오류 상세 데이터를 반환한다.
   *
   * @return 오류 상세 데이터, 상세 데이터가 없으면 {@code null}
   */
  @JsonProperty("data")
  public T data() {
    return data;
  }
}
