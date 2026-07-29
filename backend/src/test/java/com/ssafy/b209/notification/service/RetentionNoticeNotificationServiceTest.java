package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import org.assertj.core.groups.Tuple;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

/** 보관 만료 알림함 원본의 소유자별 생성과 페이로드 형태를 검증한다. */
@ExtendWith(MockitoExtension.class)
class RetentionNoticeNotificationServiceTest {

  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-29T09:00:00Z"), ZoneOffset.UTC);

  @Mock private NotificationRepository notificationRepository;
  @Captor private ArgumentCaptor<Notification> notificationCaptor;

  @Test
  void createsOneNotificationPerOwnerWithoutRelatedResource() {
    RetentionNoticeNotificationService service =
        new RetentionNoticeNotificationService(notificationRepository, CLOCK);
    AtomicLong idSequence = new AtomicLong(800L);
    given(notificationRepository.save(any(Notification.class)))
        .willAnswer(
            invocation -> {
              Notification notification = invocation.getArgument(0);
              ReflectionTestUtils.setField(notification, "id", idSequence.getAndIncrement());
              return notification;
            });

    List<CreatedNotification> created = service.createRetentionNotices(List.of(33L, 44L));

    assertThat(created)
        .extracting(
            CreatedNotification::notificationId,
            CreatedNotification::recipientUserId,
            CreatedNotification::type,
            CreatedNotification::relatedResourceType,
            CreatedNotification::relatedResourceId)
        .containsExactly(
            Tuple.tuple(800L, 33L, "RETENTION_NOTICE", null, null),
            Tuple.tuple(801L, 44L, "RETENTION_NOTICE", null, null));
    assertThat(created)
        .allSatisfy(
            notification -> {
              assertThat(notification.title()).isEqualTo("보관 기간이 곧 만료돼요");
              assertThat(notification.content()).isEqualTo("보관 기간이 만료되기 전에 확인해 주세요");
            });

    verify(notificationRepository, times(2)).save(notificationCaptor.capture());
    assertThat(notificationCaptor.getAllValues())
        .allSatisfy(
            notification -> {
              assertThat(notification.getNotificationType()).isEqualTo("RETENTION_NOTICE");
              assertThat(notification.getRelatedReportId()).isNull();
              assertThat(notification.getRelatedDrawingSessionId()).isNull();
              assertThat(notification.getRelatedPostId()).isNull();
              assertThat(notification.getDeliveryStatus()).isEqualTo("PENDING");
            });
  }

  @Test
  void returnsEmptyWhenNoOwnerGiven() {
    RetentionNoticeNotificationService service =
        new RetentionNoticeNotificationService(notificationRepository, CLOCK);

    List<CreatedNotification> created = service.createRetentionNotices(List.of());

    assertThat(created).isEmpty();
    verify(notificationRepository, never()).save(any());
  }
}
