package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.notification.repository.RetentionExpiryRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** 보관 만료 임박 알림 스케줄러의 실행 게이트, 기준일 계산, 실패 격리를 검증한다. */
@ExtendWith(MockitoExtension.class)
class RetentionNoticeSchedulerTest {

  private static final Instant NOW = Instant.parse("2026-07-29T10:00:00Z");

  @Mock private RetentionExpiryRepository expiryRepository;
  @Mock private RetentionNoticeNotificationService notificationService;
  @Mock private NotificationPushDispatcher dispatcher;

  private RetentionNoticeScheduler scheduler(RetentionNoticeProperties properties) {
    return new RetentionNoticeScheduler(
        expiryRepository,
        notificationService,
        dispatcher,
        properties,
        Clock.fixed(NOW, ZoneOffset.UTC));
  }

  private RetentionNoticeProperties properties(boolean enabled) {
    RetentionNoticeProperties properties = new RetentionNoticeProperties();
    properties.setEnabled(enabled);
    properties.setRetentionDays(180);
    properties.setNoticeDaysBefore(30);
    properties.setBatchSize(50);
    return properties;
  }

  @Test
  void doesNothingWhenDisabled() {
    assertThatCode(() -> scheduler(properties(false)).notifyExpiringRetention())
        .doesNotThrowAnyException();

    verifyNoInteractions(expiryRepository, notificationService, dispatcher);
  }

  @Test
  void queriesWithCutoffFromRetentionAndNoticeDaysAndBatchSize() {
    given(expiryRepository.findExpiringDataOwnerUserIds(any(), anyInt())).willReturn(List.of());

    scheduler(properties(true)).notifyExpiringRetention();

    ArgumentCaptor<LocalDateTime> cutoffCaptor = ArgumentCaptor.forClass(LocalDateTime.class);
    verify(expiryRepository).findExpiringDataOwnerUserIds(cutoffCaptor.capture(), eq(50));
    assertThat(cutoffCaptor.getValue())
        .isEqualTo(LocalDateTime.ofInstant(NOW, ZoneOffset.UTC).minusDays(180).plusDays(30));
    verify(notificationService, never()).createRetentionNotices(any());
    verifyNoInteractions(dispatcher);
  }

  @Test
  void dispatchesEachCreatedNoticeWhenExpiringOwnersExist() {
    given(expiryRepository.findExpiringDataOwnerUserIds(any(), anyInt()))
        .willReturn(List.of(33L, 44L));
    CreatedNotification first = notice(800L, 33L);
    CreatedNotification second = notice(801L, 44L);
    given(notificationService.createRetentionNotices(List.of(33L, 44L)))
        .willReturn(List.of(first, second));

    scheduler(properties(true)).notifyExpiringRetention();

    verify(dispatcher).dispatch(first);
    verify(dispatcher).dispatch(second);
  }

  @Test
  void continuesAfterOneDispatchFailure() {
    given(expiryRepository.findExpiringDataOwnerUserIds(any(), anyInt()))
        .willReturn(List.of(33L, 44L));
    CreatedNotification first = notice(800L, 33L);
    CreatedNotification second = notice(801L, 44L);
    given(notificationService.createRetentionNotices(List.of(33L, 44L)))
        .willReturn(List.of(first, second));
    willThrow(new RuntimeException("push failed")).given(dispatcher).dispatch(first);

    assertThatCode(() -> scheduler(properties(true)).notifyExpiringRetention())
        .doesNotThrowAnyException();

    verify(dispatcher).dispatch(second);
  }

  private CreatedNotification notice(long notificationId, long recipientUserId) {
    return new CreatedNotification(
        notificationId,
        recipientUserId,
        "RETENTION_NOTICE",
        "보관 기간이 곧 만료돼요",
        "보관 기간이 만료되기 전에 확인해 주세요",
        null,
        null);
  }
}
