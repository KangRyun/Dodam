package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.repository.AnalysisCompletedRecipientRepository;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class AnalysisCompletedNotificationServiceTest {

  private static final long REPORT_ID = 55L;
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-28T09:00:00Z"), ZoneOffset.UTC);

  @Mock private NotificationRepository notificationRepository;
  @Mock private AnalysisCompletedRecipientRepository recipientRepository;
  @Captor private ArgumentCaptor<Notification> notificationCaptor;

  @Test
  void createsOneNotificationPerGuardianWithReportPayload() {
    AnalysisCompletedNotificationService service =
        new AnalysisCompletedNotificationService(
            notificationRepository, recipientRepository, CLOCK);
    given(recipientRepository.findGuardianUserIdsByReportId(REPORT_ID))
        .willReturn(List.of(11L, 22L));
    AtomicLong idSequence = new AtomicLong(900L);
    given(notificationRepository.save(any(Notification.class)))
        .willAnswer(
            invocation -> {
              Notification notification = invocation.getArgument(0);
              ReflectionTestUtils.setField(notification, "id", idSequence.getAndIncrement());
              return notification;
            });

    List<CreatedNotification> created = service.createAnalysisCompleted(REPORT_ID);

    assertThat(created)
        .extracting(
            CreatedNotification::notificationId,
            CreatedNotification::recipientUserId,
            CreatedNotification::type,
            CreatedNotification::relatedResourceType,
            CreatedNotification::relatedResourceId)
        .containsExactly(
            org.assertj.core.groups.Tuple.tuple(900L, 11L, "ANALYSIS_COMPLETED", "REPORT", 55L),
            org.assertj.core.groups.Tuple.tuple(901L, 22L, "ANALYSIS_COMPLETED", "REPORT", 55L));
    assertThat(created)
        .allSatisfy(
            notification -> {
              assertThat(notification.title()).isEqualTo("분석이 완료됐어요");
              assertThat(notification.content()).isEqualTo("리포트를 확인해 보세요");
            });

    verify(notificationRepository, org.mockito.Mockito.times(2)).save(notificationCaptor.capture());
    List<Notification> saved = notificationCaptor.getAllValues();
    assertThat(saved)
        .allSatisfy(
            notification -> {
              assertThat(notification.getNotificationType()).isEqualTo("ANALYSIS_COMPLETED");
              assertThat(notification.getRelatedReportId()).isEqualTo(REPORT_ID);
              assertThat(notification.getRelatedDrawingSessionId()).isNull();
              assertThat(notification.getRelatedPostId()).isNull();
              assertThat(notification.getDeliveryStatus()).isEqualTo("PENDING");
            });
    assertThat(saved).extracting(Notification::getRecipientUserId).containsExactly(11L, 22L);
  }

  @Test
  void returnsEmptyWhenNoGuardianResolved() {
    AnalysisCompletedNotificationService service =
        new AnalysisCompletedNotificationService(
            notificationRepository, recipientRepository, CLOCK);
    given(recipientRepository.findGuardianUserIdsByReportId(REPORT_ID)).willReturn(List.of());

    List<CreatedNotification> created = service.createAnalysisCompleted(REPORT_ID);

    assertThat(created).isEmpty();
    verify(notificationRepository, never()).save(any());
  }
}
