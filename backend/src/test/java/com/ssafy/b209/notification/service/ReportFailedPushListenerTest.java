package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.report.service.ReportGenerationFailedEvent;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 실패 알림 발송이 본 흐름을 깨지 않는지 확인한다.
 *
 * <p>알림은 리포트 실패 기록의 부수효과다. 여기서 예외가 새면 실패 기록 자체가 롤백되거나 재시도 배치가 멈춘다.
 */
@ExtendWith(MockitoExtension.class)
class ReportFailedPushListenerTest {

  private static final Long REPORT_ID = 55L;

  @Mock private ReportFailedNotificationService notificationService;
  @Mock private NotificationPushDispatcher dispatcher;

  private ReportFailedPushListener listener() {
    return new ReportFailedPushListener(notificationService, dispatcher);
  }

  @Test
  void dispatchesEachCreatedNotification() {
    CreatedNotification first = notification(900L, 11L);
    CreatedNotification second = notification(901L, 22L);
    given(notificationService.createReportFailed(REPORT_ID)).willReturn(List.of(first, second));

    listener().onReportGenerationFailed(new ReportGenerationFailedEvent(REPORT_ID));

    verify(dispatcher).dispatch(first);
    verify(dispatcher).dispatch(second);
  }

  /** 알림함 저장이 실패하면 발송할 원본이 없다. 예외를 위로 던지지 않는다. */
  @Test
  void swallowsCreationFailureAndSkipsDispatch() {
    given(notificationService.createReportFailed(REPORT_ID))
        .willThrow(new IllegalStateException("db down"));

    assertThatCode(
            () -> listener().onReportGenerationFailed(new ReportGenerationFailedEvent(REPORT_ID)))
        .doesNotThrowAnyException();
    verify(dispatcher, never()).dispatch(any());
  }

  /** 보호자 한 명에게 못 보냈다고 나머지 보호자를 건너뛰지 않는다. */
  @Test
  void continuesAfterOneDispatchFailure() {
    CreatedNotification first = notification(900L, 11L);
    CreatedNotification second = notification(901L, 22L);
    given(notificationService.createReportFailed(REPORT_ID)).willReturn(List.of(first, second));
    willThrow(new RuntimeException("push failed")).given(dispatcher).dispatch(first);

    assertThatCode(
            () -> listener().onReportGenerationFailed(new ReportGenerationFailedEvent(REPORT_ID)))
        .doesNotThrowAnyException();
    verify(dispatcher).dispatch(second);
  }

  private CreatedNotification notification(long notificationId, long recipientUserId) {
    return new CreatedNotification(
        notificationId,
        recipientUserId,
        "ANALYSIS_FAILED",
        "리포트를 만들지 못했어요",
        "앱에서 다시 시도해 주세요",
        "REPORT",
        REPORT_ID);
  }
}
