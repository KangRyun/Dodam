package com.ssafy.b209.infrastructure.push;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.ssafy.b209.notification.push.PushMessage;
import com.ssafy.b209.notification.push.PushSendOutcome;
import com.ssafy.b209.notification.push.PushSender;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Conditional;
import org.springframework.stereotype.Component;

/**
 * FCM으로 data-only 메시지를 발송하는 {@link PushSender} 구현이다.
 *
 * <p>{@code setNotification}을 호출하지 않아 OS 자동 표시를 막고 표시 통제를 앱에 남긴다(계약 §0-1). {@code
 * UNREGISTERED}·{@code INVALID_ARGUMENT}는 죽은 Token으로 판정하고, 그 밖의 오류는 일시 오류로 본다(§5.3). 오류는 FCM 오류코드만
 * 로그로 남기며 Token·본문은 남기지 않는다(§5.4).
 */
@Component
@Conditional(FcmAvailableCondition.class)
public class FcmPushSender implements PushSender {

  private static final Logger log = LoggerFactory.getLogger(FcmPushSender.class);

  private final FirebaseMessaging firebaseMessaging;

  /**
   * 발송에 사용할 {@link FirebaseMessaging}를 주입받는다.
   *
   * @param firebaseMessaging 초기화된 발송 Client
   */
  public FcmPushSender(FirebaseMessaging firebaseMessaging) {
    this.firebaseMessaging = firebaseMessaging;
  }

  @Override
  public boolean isEnabled() {
    return true;
  }

  @Override
  public PushSendOutcome send(PushMessage message) {
    Message fcmMessage =
        Message.builder().putAllData(message.data()).setToken(message.token()).build();
    try {
      firebaseMessaging.send(fcmMessage);
      return PushSendOutcome.SENT;
    } catch (FirebaseMessagingException exception) {
      MessagingErrorCode errorCode = exception.getMessagingErrorCode();
      log.warn("FCM 발송에 실패했습니다. errorCode={}", errorCode);
      if (errorCode == MessagingErrorCode.UNREGISTERED
          || errorCode == MessagingErrorCode.INVALID_ARGUMENT) {
        return PushSendOutcome.TOKEN_INVALID;
      }
      return PushSendOutcome.TEMPORARY_FAILURE;
    }
  }
}
