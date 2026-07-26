package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.dto.response.NotificationReadResponse;
import com.ssafy.b209.notification.exception.NotificationErrorCode;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

/** 읽음 처리의 멱등성과 남의 알림 존재 은닉을 검증한다. */
@ExtendWith(MockitoExtension.class)
class NotificationReadServiceTest {

  private static final Long USER_ID = 41L;
  private static final Long NOTIFICATION_ID = 900L;
  private static final Instant NOW = Instant.parse("2026-07-26T12:00:00Z");
  private static final LocalDateTime EARLIER = LocalDateTime.parse("2026-07-25T09:00:00");

  @Mock private NotificationRepository notificationRepository;

  private NotificationReadService service;

  @BeforeEach
  void setUp() {
    service = new NotificationReadService(notificationRepository, Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void marksUnreadNotificationWithServerTime() {
    Notification notification = notification(null);
    given(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
        .willReturn(Optional.of(notification));
    given(notificationRepository.saveAndFlush(notification)).willReturn(notification);

    NotificationReadResponse response = service.markRead(USER_ID, NOTIFICATION_ID);

    assertThat(response.notificationId()).isEqualTo(NOTIFICATION_ID);
    assertThat(response.readAt()).isEqualTo(LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
  }

  @Test
  void keepsFirstReadTimeAndSkipsWriteWhenAlreadyRead() {
    Notification notification = notification(EARLIER);
    given(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
        .willReturn(Optional.of(notification));

    NotificationReadResponse response = service.markRead(USER_ID, NOTIFICATION_ID);

    // 재호출이 최초 읽은 시각을 덮어쓰면 목록 재진입만으로 기록이 바뀐다.
    assertThat(response.readAt()).isEqualTo(EARLIER);
    verify(notificationRepository, never()).saveAndFlush(any(Notification.class));
  }

  @Test
  void hidesNotificationsOwnedByAnotherUserBehindNotFound() {
    given(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
        .willReturn(Optional.empty());

    assertThatThrownBy(() -> service.markRead(USER_ID, NOTIFICATION_ID))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(NotificationErrorCode.NOTIFICATION_NOT_FOUND));
  }

  private Notification notification(LocalDateTime readAt) {
    Notification notification = new Notification() {};
    ReflectionTestUtils.setField(notification, "id", NOTIFICATION_ID);
    ReflectionTestUtils.setField(notification, "recipientUserId", USER_ID);
    ReflectionTestUtils.setField(notification, "readAt", readAt);
    return notification;
  }
}
