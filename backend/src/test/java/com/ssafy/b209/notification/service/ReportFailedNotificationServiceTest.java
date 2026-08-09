package com.ssafy.b209.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.domain.NotificationTypes;
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

/**
 * 리포트 최종 실패 알림이 보호자마다 한 건씩 남는지, 문구가 중립인지 확인한다.
 *
 * <p>아이 화면은 리포트를 기다리지 않고 넘어가므로 이 알림이 실패를 알리는 유일한 경로다.
 */
@ExtendWith(MockitoExtension.class)
class ReportFailedNotificationServiceTest {

  private static final long REPORT_ID = 55L;
  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-08-09T09:00:00Z"), ZoneOffset.UTC);

  @Mock private NotificationRepository notificationRepository;
  @Mock private AnalysisCompletedRecipientRepository recipientRepository;
  @Captor private ArgumentCaptor<Notification> notificationCaptor;

  private ReportFailedNotificationService service() {
    return new ReportFailedNotificationService(notificationRepository, recipientRepository, CLOCK);
  }

  @Test
  void createsOneNotificationPerGuardianWithReportPayload() {
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

    List<CreatedNotification> created = service().createReportFailed(REPORT_ID);

    assertThat(created)
        .extracting(
            CreatedNotification::notificationId,
            CreatedNotification::recipientUserId,
            CreatedNotification::type,
            CreatedNotification::relatedResourceType,
            CreatedNotification::relatedResourceId)
        .containsExactly(
            org.assertj.core.groups.Tuple.tuple(900L, 11L, "ANALYSIS_FAILED", "REPORT", 55L),
            org.assertj.core.groups.Tuple.tuple(901L, 22L, "ANALYSIS_FAILED", "REPORT", 55L));

    verify(notificationRepository, org.mockito.Mockito.times(2)).save(notificationCaptor.capture());
    List<Notification> saved = notificationCaptor.getAllValues();
    assertThat(saved)
        .allSatisfy(
            notification -> {
              assertThat(notification.getNotificationType()).isEqualTo("ANALYSIS_FAILED");
              assertThat(notification.getRelatedReportId()).isEqualTo(REPORT_ID);
              assertThat(notification.getRelatedDrawingSessionId()).isNull();
              assertThat(notification.getRelatedPostId()).isNull();
              assertThat(notification.getDeliveryStatus()).isEqualTo("PENDING");
            });
    assertThat(saved).extracting(Notification::getRecipientUserId).containsExactly(11L, 22L);
  }

  /** DB CHECK 제약과 같은 어휘를 써야 저장이 통과한다. */
  @Test
  void usesTypeAllowedByDatabaseConstraint() {
    given(recipientRepository.findGuardianUserIdsByReportId(REPORT_ID)).willReturn(List.of(11L));
    given(notificationRepository.save(any(Notification.class)))
        .willAnswer(
            invocation -> {
              Notification notification = invocation.getArgument(0);
              ReflectionTestUtils.setField(notification, "id", 900L);
              return notification;
            });

    List<CreatedNotification> created = service().createReportFailed(REPORT_ID);

    assertThat(NotificationTypes.isAllowed(created.get(0).type())).isTrue();
  }

  /**
   * 문구에 아동 발화·그림 해석·위험 신호·실패 원인이 섞이면 안 된다 (가드레일 9절).
   *
   * <p>푸시 본문은 잠금화면에 그대로 뜬다. 내용은 보호자가 앱을 열어 확인한다.
   */
  @Test
  void keepsCopyNeutralWithoutSensitiveContent() {
    given(recipientRepository.findGuardianUserIdsByReportId(REPORT_ID)).willReturn(List.of(11L));
    given(notificationRepository.save(any(Notification.class)))
        .willAnswer(
            invocation -> {
              Notification notification = invocation.getArgument(0);
              ReflectionTestUtils.setField(notification, "id", 900L);
              return notification;
            });

    CreatedNotification created = service().createReportFailed(REPORT_ID).get(0);

    assertThat(created.title()).isEqualTo("리포트를 만들지 못했어요");
    assertThat(created.content()).isEqualTo("앱에서 다시 시도해 주세요");
    // 내부 분류 코드·아동 정보·해석 어휘가 새어 나가지 않는다.
    assertThat(created.title() + created.content())
        .doesNotContainIgnoringCase("OBSERVATION")
        .doesNotContainIgnoringCase("INVALID")
        .doesNotContainIgnoringCase("STORAGE")
        .doesNotContain("불안")
        .doesNotContain("위험")
        .doesNotContain("그림")
        .doesNotContain("아이");
  }

  @Test
  void returnsEmptyWhenNoGuardianResolved() {
    given(recipientRepository.findGuardianUserIdsByReportId(REPORT_ID)).willReturn(List.of());

    assertThat(service().createReportFailed(REPORT_ID)).isEmpty();
    verify(notificationRepository, never()).save(any());
  }
}
