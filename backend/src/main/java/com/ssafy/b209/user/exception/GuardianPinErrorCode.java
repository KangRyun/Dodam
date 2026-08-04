package com.ssafy.b209.user.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/**
 * 보호자 PIN API 의 오류 어휘다 (S15P11B209-879).
 *
 * <p>메시지에 PIN 원문이나 해시를 넣지 않는다. 남은 시도 횟수·잠금 해제 시각처럼 클라이언트가 화면에 써야 하는 값은 메시지가 아니라 응답 {@code data} 로
 * 내려간다({@link GuardianPinException}).
 */
public enum GuardianPinErrorCode implements ErrorCode {

  /**
   * PIN 형식 위반이다.
   *
   * <p><b>HTTP 경로로는 도달하지 않는다.</b> 요청 DTO 의 {@code @NotBlank @Pattern("^\\d{4}$")} 와 Controller 의
   * {@code @Valid} 가 먼저 걸러 실제 응답은 {@code COMMON_400_001} 이고 {@code data} 에 {@code
   * ValidationErrorData} 가 실린다. 이 코드는 Bean Validation 을 거치지 않는 서비스 내부 직접 호출에 대한 가드로만 유효하다. Jira
   * S15P11B209-879 의 오류 표에 이 코드가 "400, data 없음"으로 적혀 있으나 사실과 다르다({@code
   * docs/api/guardian-pin-contract.md} 참고).
   */
  PIN_INVALID(HttpStatus.BAD_REQUEST, "PIN_INVALID", "PIN은 숫자 4자리여야 합니다."),
  PIN_MISMATCH(HttpStatus.UNAUTHORIZED, "PIN_MISMATCH", "PIN이 일치하지 않습니다."),
  PIN_NOT_CONFIGURED(HttpStatus.CONFLICT, "PIN_NOT_CONFIGURED", "설정된 PIN이 없습니다."),
  PIN_ALREADY_CONFIGURED(HttpStatus.CONFLICT, "PIN_ALREADY_CONFIGURED", "이미 PIN이 설정되어 있습니다."),
  PIN_RESET_REQUIRED(HttpStatus.CONFLICT, "PIN_RESET_REQUIRED", "PIN을 초기화하려면 소셜 로그인으로 다시 인증해 주세요."),

  /** 423 Locked — 요청 자체는 올바르지만 자원이 일시적으로 잠겨 있다는 뜻이라 이 상황에 정확히 맞는다. */
  PIN_LOCKED(HttpStatus.LOCKED, "PIN_LOCKED", "PIN 입력이 잠겨 있습니다. 잠시 후 다시 시도해 주세요."),

  /**
   * pepper 시크릿이 없어 PIN 을 다룰 수 없는 상태다.
   *
   * <p>기동을 막지 않고 이 API 만 거부한다. PIN 과 무관한 기능까지 멈추면 손실이 더 크다(기기 Token 암호화 키 미구성 처리와 같은 방식).
   */
  PIN_UNAVAILABLE(
      HttpStatus.SERVICE_UNAVAILABLE, "PIN_UNAVAILABLE", "PIN 기능을 사용할 수 없습니다. 관리자에게 문의해 주세요.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  GuardianPinErrorCode(HttpStatus httpStatus, String code, String message) {
    this.httpStatus = httpStatus;
    this.code = code;
    this.message = message;
  }

  @Override
  public HttpStatus getHttpStatus() {
    return httpStatus;
  }

  @Override
  public String getCode() {
    return code;
  }

  @Override
  public String getMessage() {
    return message;
  }
}
