package com.ssafy.b209.infrastructure.push;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.ssafy.b209.notification.push.PushMessage;
import com.ssafy.b209.notification.push.PushSendOutcome;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class FcmPushSenderTest {

  @Mock private FirebaseMessaging firebaseMessaging;

  private static final PushMessage MESSAGE =
      new PushMessage(
          "plain-token",
          Map.of(
              "notificationId",
              "900",
              "type",
              "ANALYSIS_COMPLETED",
              "title",
              "분석이 완료됐어요",
              "content",
              "리포트를 확인해 보세요",
              "relatedResourceType",
              "REPORT",
              "relatedResourceId",
              "55"));

  @Test
  void reportsSentOnSuccess() throws FirebaseMessagingException {
    given(firebaseMessaging.send(any(Message.class))).willReturn("projects/dodam/messages/1");

    PushSendOutcome outcome = new FcmPushSender(firebaseMessaging).send(MESSAGE);

    assertThat(outcome).isEqualTo(PushSendOutcome.SENT);
  }

  @Test
  void reportsTokenInvalidOnUnregistered() throws FirebaseMessagingException {
    FirebaseMessagingException exception = exceptionWithCode(MessagingErrorCode.UNREGISTERED);
    given(firebaseMessaging.send(any(Message.class))).willThrow(exception);

    PushSendOutcome outcome = new FcmPushSender(firebaseMessaging).send(MESSAGE);

    assertThat(outcome).isEqualTo(PushSendOutcome.TOKEN_INVALID);
  }

  @Test
  void reportsTokenInvalidOnInvalidArgument() throws FirebaseMessagingException {
    FirebaseMessagingException exception = exceptionWithCode(MessagingErrorCode.INVALID_ARGUMENT);
    given(firebaseMessaging.send(any(Message.class))).willThrow(exception);

    PushSendOutcome outcome = new FcmPushSender(firebaseMessaging).send(MESSAGE);

    assertThat(outcome).isEqualTo(PushSendOutcome.TOKEN_INVALID);
  }

  @Test
  void reportsTemporaryFailureOnOtherErrors() throws FirebaseMessagingException {
    FirebaseMessagingException exception = exceptionWithCode(MessagingErrorCode.INTERNAL);
    given(firebaseMessaging.send(any(Message.class))).willThrow(exception);

    PushSendOutcome outcome = new FcmPushSender(firebaseMessaging).send(MESSAGE);

    assertThat(outcome).isEqualTo(PushSendOutcome.TEMPORARY_FAILURE);
  }

  private FirebaseMessagingException exceptionWithCode(MessagingErrorCode code) {
    FirebaseMessagingException exception = mock(FirebaseMessagingException.class);
    given(exception.getMessagingErrorCode()).willReturn(code);
    return exception;
  }
}
