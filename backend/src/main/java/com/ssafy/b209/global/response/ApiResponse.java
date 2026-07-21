package com.ssafy.b209.global.response;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import java.util.Objects;

/**
 * API의 일반 성공 결과를 일관된 JSON 구조로 감싸는 불변 응답 객체다.
 *
 * <p>HTTP Status는 응답 Body에 포함하지 않고 Controller의 {@code ResponseEntity}로 전달한다. HTTP 204 응답에는 이 객체를
 * 사용하지 않는다.
 *
 * @param <T> 응답 데이터 타입
 */
@JsonPropertyOrder({"success", "code", "message", "data"})
public final class ApiResponse<T> {

  private final boolean success;
  private final String code;
  private final String message;
  private final T data;

  private ApiResponse(String code, String message, T data) {
    this.success = true;
    this.code = code;
    this.message = message;
    this.data = data;
  }

  /**
   * 데이터가 포함된 기본 HTTP 200 성공 응답을 생성한다.
   *
   * @param data 응답 데이터
   * @param <T> 응답 데이터 타입
   * @return 기본 성공 코드와 데이터를 가진 응답
   */
  public static <T> ApiResponse<T> ok(T data) {
    return of(CommonSuccessCode.OK, data);
  }

  /**
   * 데이터가 없는 기본 HTTP 200 성공 응답을 생성한다.
   *
   * @return {@code data}가 {@code null}인 기본 성공 응답
   */
  public static ApiResponse<Void> ok() {
    return of(CommonSuccessCode.OK, null);
  }

  /**
   * 지정한 성공 코드와 데이터로 응답을 생성한다.
   *
   * @param successCode 응답 코드, HTTP Status와 기본 메시지를 제공하는 성공 코드
   * @param data 응답 데이터
   * @param <T> 응답 데이터 타입
   * @return 지정한 성공 코드의 코드와 메시지를 가진 응답
   * @throws NullPointerException {@code successCode}가 {@code null}인 경우
   */
  public static <T> ApiResponse<T> of(SuccessCode successCode, T data) {
    Objects.requireNonNull(successCode, "successCode must not be null");
    return new ApiResponse<>(successCode.getCode(), successCode.getMessage(), data);
  }

  /**
   * 요청 성공 여부를 반환한다.
   *
   * @return 항상 {@code true}
   */
  @JsonProperty("success")
  public boolean success() {
    return success;
  }

  /**
   * 클라이언트가 성공 상황을 식별할 애플리케이션 코드를 반환한다.
   *
   * @return 성공 코드
   */
  @JsonProperty("code")
  public String code() {
    return code;
  }

  /**
   * 성공 상황의 기본 설명을 반환한다.
   *
   * @return 성공 메시지
   */
  @JsonProperty("message")
  public String message() {
    return message;
  }

  /**
   * 응답에 포함할 실제 데이터를 반환한다.
   *
   * @return 응답 데이터, 데이터가 없는 HTTP 200 응답이면 {@code null}
   */
  @JsonProperty("data")
  public T data() {
    return data;
  }
}
