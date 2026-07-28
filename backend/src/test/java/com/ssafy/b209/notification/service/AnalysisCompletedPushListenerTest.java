package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.report.service.AnalysisCompletedEvent;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AnalysisCompletedPushListenerTest {

  private static final Long REPORT_ID = 55L;

  @Mock private AnalysisCompletedNotificationService notificationService;
  @Mock private NotificationPushDispatcher dispatcher;

  private AnalysisCompletedPushListener listener() {
    return new AnalysisCompletedPushListener(notificationService, dispatcher);
  }

  @Test
  void dispatchesEachCreatedNotification() {
    CreatedNotification first = notification(900L, 11L);
    CreatedNotification second = notification(901L, 22L);
    given(notificationService.createAnalysisCompleted(REPORT_ID))
        .willReturn(List.of(first, second));

    listener().onAnalysisCompleted(new AnalysisCompletedEvent(REPORT_ID));

    verify(dispatcher).dispatch(first);
    verify(dispatcher).dispatch(second);
  }

  @Test
  void swallowsCreationFailureAndSkipsDispatch() {
    given(notificationService.createAnalysisCompleted(REPORT_ID))
        .willThrow(new IllegalStateException("db down"));

    assertThatCode(() -> listener().onAnalysisCompleted(new AnalysisCompletedEvent(REPORT_ID)))
        .doesNotThrowAnyException();
    verify(dispatcher, never()).dispatch(any());
  }

  @Test
  void continuesAfterOneDispatchFailure() {
    CreatedNotification first = notification(900L, 11L);
    CreatedNotification second = notification(901L, 22L);
    given(notificationService.createAnalysisCompleted(REPORT_ID))
        .willReturn(List.of(first, second));
    willThrow(new RuntimeException("push failed")).given(dispatcher).dispatch(first);

    assertThatCode(() -> listener().onAnalysisCompleted(new AnalysisCompletedEvent(REPORT_ID)))
        .doesNotThrowAnyException();
    verify(dispatcher).dispatch(second);
  }

  private CreatedNotification notification(long notificationId, long recipientUserId) {
    return new CreatedNotification(
        notificationId,
        recipientUserId,
        "ANALYSIS_COMPLETED",
        "분석이 완료됐어요",
        "리포트를 확인해 보세요",
        "REPORT",
        REPORT_ID);
  }
}
