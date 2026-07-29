package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** 약관 변경 트리거 진입점의 생성→발송 순서와 실패 격리를 검증한다. */
@ExtendWith(MockitoExtension.class)
class TermsChangeNotifierTest {

  private static final String TERM_CODE = "PRIVACY_POLICY";
  private static final String VERSION = "2.0";

  @Mock private TermsChangeNotificationService notificationService;
  @Mock private NotificationPushDispatcher dispatcher;

  private TermsChangeNotifier notifier() {
    return new TermsChangeNotifier(notificationService, dispatcher);
  }

  @Test
  void dispatchesEachCreatedNotification() {
    CreatedNotification first = notification(700L, 11L);
    CreatedNotification second = notification(701L, 22L);
    given(notificationService.createConsentUpdated(TERM_CODE)).willReturn(List.of(first, second));

    notifier().notifyTermsUpdated(TERM_CODE, VERSION);

    verify(dispatcher).dispatch(first);
    verify(dispatcher).dispatch(second);
  }

  @Test
  void swallowsCreationFailureAndSkipsDispatch() {
    given(notificationService.createConsentUpdated(TERM_CODE))
        .willThrow(new IllegalStateException("db down"));

    assertThatCode(() -> notifier().notifyTermsUpdated(TERM_CODE, VERSION))
        .doesNotThrowAnyException();
    verify(dispatcher, never()).dispatch(any());
  }

  @Test
  void continuesAfterOneDispatchFailure() {
    CreatedNotification first = notification(700L, 11L);
    CreatedNotification second = notification(701L, 22L);
    given(notificationService.createConsentUpdated(TERM_CODE)).willReturn(List.of(first, second));
    willThrow(new RuntimeException("push failed")).given(dispatcher).dispatch(first);

    assertThatCode(() -> notifier().notifyTermsUpdated(TERM_CODE, VERSION))
        .doesNotThrowAnyException();
    verify(dispatcher).dispatch(second);
  }

  private CreatedNotification notification(long notificationId, long recipientUserId) {
    return new CreatedNotification(
        notificationId,
        recipientUserId,
        "CONSENT_UPDATED",
        "약관이 변경되었어요",
        "변경된 약관을 확인해 주세요",
        null,
        null);
  }
}
