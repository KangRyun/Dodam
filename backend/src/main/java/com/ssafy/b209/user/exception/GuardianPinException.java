package com.ssafy.b209.user.exception;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ErrorCode;
import com.ssafy.b209.user.dto.response.GuardianPinStatusResponse;

/**
 * 보호자 PIN 실패 응답에 현재 상태를 함께 실어 보내는 예외다 (S15P11B209-879).
 *
 * <p>{@code PIN_MISMATCH} 는 "몇 번 남았는지", {@code PIN_LOCKED} 는 "언제 풀리는지"를 함께 줘야 화면을 만들 수 있다. 그 값을 오류
 * 메시지 문자열에 섞으면 클라이언트가 문구를 파싱해야 하므로, 성공 응답과 <b>같은 구조체</b>를 오류 응답 {@code data} 에 싣는다.
 *
 * <p>상태를 실을 필요가 없는 오류({@code PIN_INVALID} 등)는 그대로 {@link BusinessException} 을 쓴다.
 */
public class GuardianPinException extends BusinessException {

  private final transient GuardianPinStatusResponse status;

  /**
   * 오류 코드와 함께 내려보낼 PIN 상태를 담는다.
   *
   * @param errorCode 오류 코드
   * @param status 같은 시점의 PIN 상태이며 PIN 원문·해시를 포함하지 않는다
   */
  public GuardianPinException(ErrorCode errorCode, GuardianPinStatusResponse status) {
    super(errorCode);
    this.status = status;
  }

  /**
   * @return 오류 응답 {@code data} 에 실을 PIN 상태
   */
  public GuardianPinStatusResponse getStatus() {
    return status;
  }
}
