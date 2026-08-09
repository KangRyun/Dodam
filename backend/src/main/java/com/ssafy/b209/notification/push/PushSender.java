package com.ssafy.b209.notification.push;

/**
 * 한 기기 Token에 data-only 푸시 메시지를 보내는 Application 경계다.
 *
 * <p>구현 선택은 {@code app.push.fcm.enabled}에 따라 결정된다. 발송이 꺼진 환경에서는 no-op 구현이 활성화되며, 호출부는 {@link
 * #isEnabled()}로 발송 가능 여부를 먼저 확인해 불필요한 복호화를 피한다.
 */
public interface PushSender {

  /**
   * 실제 발송이 가능한 구현인지 알려준다.
   *
   * @return FCM 발송이 켜져 있으면 {@code true}, no-op이면 {@code false}
   */
  boolean isEnabled();

  /**
   * data-only 메시지를 한 기기 Token으로 보낸다.
   *
   * @param message 발송 대상 Token과 문자열 data
   * @return 발송 결과이며 죽은 Token 정리와 상태 반영에 사용한다
   */
  PushSendOutcome send(PushMessage message);
}
