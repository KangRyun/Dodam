package com.ssafy.b209.notification.push;

/**
 * 한 기기에 대한 푸시 발송 결과다.
 *
 * <p>죽은 Token 정리(계약 §5.3)와 알림 전송 상태 반영(§5.1)의 근거로 사용한다.
 */
public enum PushSendOutcome {

  /** 발송에 성공했다. */
  SENT,

  /** Token이 만료·삭제·형식 오류라 비활성화해야 한다. */
  TOKEN_INVALID,

  /** 네트워크·5xx 같은 일시 오류로 Token은 유지한다. */
  TEMPORARY_FAILURE
}
