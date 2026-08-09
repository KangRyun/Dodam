package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.dto.response.NotificationMarkAllReadResponse;
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
    // Entity의 LocalDateTime은 UTC 벽시계이므로 응답 Instant는 시계가 준 instant와 같아야 한다.
    assertThat(response.readAt()).isEqualTo(NOW);
  }

  @Test
  void keepsFirstReadTimeAndSkipsWriteWhenAlreadyRead() {
    Notification notification = notification(EARLIER);
    given(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
        .willReturn(Optional.of(notification));

    NotificationReadResponse response = service.markRead(USER_ID, NOTIFICATION_ID);

    // 재호출이 최초 읽은 시각을 덮어쓰면 목록 재진입만으로 기록이 바뀐다.
    assertThat(response.readAt()).isEqualTo(EARLIER.toInstant(ZoneOffset.UTC));
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

  @Test
  void marksAllUnreadNotificationsWithServerTimeWhenNoTypeGiven() {
    given(notificationRepository.markAllReadByRecipient(eq(USER_ID), isNull(), any()))
        .willReturn(3);

    NotificationMarkAllReadResponse response = service.markAllRead(USER_ID, null);

    assertThat(response.updatedCount()).isEqualTo(3);
    // 응답은 UTC instant로, DB에 넘기는 값은 UTC 벽시계 LocalDateTime으로 같은 시각을 가리킨다.
    assertThat(response.readAt()).isEqualTo(NOW);
    verify(notificationRepository)
        .markAllReadByRecipient(USER_ID, null, LocalDateTime.ofInstant(NOW, ZoneOffset.UTC));
  }

  @Test
  void marksOnlyRequestedTypeWhenTypeGiven() {
    given(
            notificationRepository.markAllReadByRecipient(
                eq(USER_ID), eq("ANALYSIS_COMPLETED"), any()))
        .willReturn(2);

    NotificationMarkAllReadResponse response = service.markAllRead(USER_ID, "ANALYSIS_COMPLETED");

    assertThat(response.updatedCount()).isEqualTo(2);
    verify(notificationRepository)
        .markAllReadByRecipient(eq(USER_ID), eq("ANALYSIS_COMPLETED"), any(LocalDateTime.class));
  }

  @Test
  void returnsZeroCountAndNullReadTimeWhenNothingIsUnread() {
    given(notificationRepository.markAllReadByRecipient(eq(USER_ID), isNull(), any()))
        .willReturn(0);

    NotificationMarkAllReadResponse response = service.markAllRead(USER_ID, "  ");

    // 공백 type은 전체 처리로 정규화되고, 바뀐 건이 없으면 시각을 만들지 않는다.
    assertThat(response.updatedCount()).isZero();
    assertThat(response.readAt()).isNull();
    verify(notificationRepository).markAllReadByRecipient(eq(USER_ID), isNull(), any());
  }

  @Test
  void rejectsTypeOutsideVocabularyWithoutTouchingTheRepository() {
    assertThatThrownBy(() -> service.markAllRead(USER_ID, "UNKNOWN_TYPE"))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(CommonErrorCode.INVALID_INPUT_VALUE));
    verify(notificationRepository, never()).markAllReadByRecipient(any(), anyString(), any());
  }

  private Notification notification(LocalDateTime readAt) {
    Notification notification = new Notification() {};
    ReflectionTestUtils.setField(notification, "id", NOTIFICATION_ID);
    ReflectionTestUtils.setField(notification, "recipientUserId", USER_ID);
    ReflectionTestUtils.setField(notification, "readAt", readAt);
    return notification;
  }
}
