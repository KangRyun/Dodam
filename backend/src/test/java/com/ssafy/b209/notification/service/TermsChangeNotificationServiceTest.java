package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.repository.NotificationRepository;
import com.ssafy.b209.notification.repository.TermsChangeRecipientRepository;
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

/** 약관 변경 알림함 원본의 수신자 선정과 페이로드 형태를 검증한다. */
@ExtendWith(MockitoExtension.class)
class TermsChangeNotificationServiceTest {

  private static final String TERM_CODE = "PRIVACY_POLICY";
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-29T09:00:00Z"), ZoneOffset.UTC);

  @Mock private NotificationRepository notificationRepository;
  @Mock private TermsChangeRecipientRepository recipientRepository;
  @Captor private ArgumentCaptor<Notification> notificationCaptor;

  @Test
  void createsOneNotificationPerActiveConsentUserWithoutRelatedResource() {
    TermsChangeNotificationService service =
        new TermsChangeNotificationService(notificationRepository, recipientRepository, CLOCK);
    given(recipientRepository.findActiveConsentUserIdsByTermCode(TERM_CODE))
        .willReturn(List.of(11L, 22L));
    AtomicLong idSequence = new AtomicLong(700L);
    given(notificationRepository.save(any(Notification.class)))
        .willAnswer(
            invocation -> {
              Notification notification = invocation.getArgument(0);
              ReflectionTestUtils.setField(notification, "id", idSequence.getAndIncrement());
              return notification;
            });

    List<CreatedNotification> created = service.createConsentUpdated(TERM_CODE);

    assertThat(created)
        .extracting(
            CreatedNotification::notificationId,
            CreatedNotification::recipientUserId,
            CreatedNotification::type,
            CreatedNotification::relatedResourceType,
            CreatedNotification::relatedResourceId)
        .containsExactly(
            Tuple.tuple(700L, 11L, "CONSENT_UPDATED", null, null),
            Tuple.tuple(701L, 22L, "CONSENT_UPDATED", null, null));
    assertThat(created)
        .allSatisfy(
            notification -> {
              assertThat(notification.title()).isEqualTo("약관이 변경되었어요");
              assertThat(notification.content()).isEqualTo("변경된 약관을 확인해 주세요");
            });

    verify(notificationRepository, times(2)).save(notificationCaptor.capture());
    assertThat(notificationCaptor.getAllValues())
        .allSatisfy(
            notification -> {
              assertThat(notification.getNotificationType()).isEqualTo("CONSENT_UPDATED");
              assertThat(notification.getRelatedReportId()).isNull();
              assertThat(notification.getRelatedDrawingSessionId()).isNull();
              assertThat(notification.getRelatedPostId()).isNull();
              assertThat(notification.getDeliveryStatus()).isEqualTo("PENDING");
            });
    assertThat(notificationCaptor.getAllValues())
        .extracting(Notification::getRecipientUserId)
        .containsExactly(11L, 22L);
  }

  @Test
  void returnsEmptyWhenNoActiveConsentUserResolved() {
    TermsChangeNotificationService service =
        new TermsChangeNotificationService(notificationRepository, recipientRepository, CLOCK);
    given(recipientRepository.findActiveConsentUserIdsByTermCode(TERM_CODE)).willReturn(List.of());

    List<CreatedNotification> created = service.createConsentUpdated(TERM_CODE);

    assertThat(created).isEmpty();
    verify(notificationRepository, never()).save(any());
  }
}
