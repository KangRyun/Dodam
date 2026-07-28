package com.ssafy.b209.infrastructure.push;

import com.ssafy.b209.notification.push.PushMessage;
import com.ssafy.b209.notification.push.PushSendOutcome;
import com.ssafy.b209.notification.push.PushSender;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * FCM 발송이 꺼진 기본 환경에서 활성화되는 no-op {@link PushSender}다.
 *
 * <p>발송을 조용히 건너뛰며(계약 §0-6) 자격증명 없이도 부팅한다. 호출부는 {@link #isEnabled()}가 {@code false}이면 발송을 시도하지 않으므로
 * {@link #send(PushMessage)}는 실행되지 않는다.
 */
@Component
@ConditionalOnProperty(
    prefix = "app.push.fcm",
    name = "enabled",
    havingValue = "false",
    matchIfMissing = true)
public class NoopPushSender implements PushSender {

  @Override
  public boolean isEnabled() {
    return false;
  }

  @Override
  public PushSendOutcome send(PushMessage message) {
    return PushSendOutcome.TEMPORARY_FAILURE;
  }
}
